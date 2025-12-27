//+------------------------------------------------------------------+
//|                                   DBasket_CorrelationEngine.mqh  |
//|                                   D-Basket Correlation Hedging EA |
//|                                   Correlation Calculation Module  |
//+------------------------------------------------------------------+
#property copyright "D-Basket EA"
#property version   "1.00"
#property strict

#ifndef DBASKET_CORRELATIONENGINE_MQH
#define DBASKET_CORRELATIONENGINE_MQH

#include "DBasket_Defines.mqh"
#include "DBasket_Structures.mqh"
#include "DBasket_Logger.mqh"

//+------------------------------------------------------------------+
//| Correlation Engine Class                                          |
//| Handles price data collection, correlation, and z-score calc      |
//+------------------------------------------------------------------+
class CCorrelationEngine
{
private:
   // Configuration
   string            m_symbols[NUM_SYMBOLS]; // Symbol names
   int               m_lookbackPeriod;       // Rolling window size
   ENUM_TIMEFRAMES   m_timeframe;            // Timeframe for data
   int               m_updateIntervalSec;    // Cache update interval
   
   // Price buffers for each symbol
   PriceHistoryBuffer m_priceBuffers[NUM_SYMBOLS];
   
   // Cached calculation results
   CorrelationData   m_cache;
   datetime          m_lastCalculationTime;
   datetime          m_lastBarTime[NUM_SYMBOLS];
   
   // State
   bool              m_isInitialized;
   bool              m_isWarmedUp;
   
   //+------------------------------------------------------------------+
   //| Calculate mean of array                                           |
   //+------------------------------------------------------------------+
   double CalculateMean(const double &arr[], int size)
   {
      if(size <= 0)
         return 0;
         
      double sum = 0;
      for(int i = 0; i < size; i++)
         sum += arr[i];
         
      return sum / size;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate standard deviation                                      |
   //+------------------------------------------------------------------+
   double CalculateStdDev(const double &arr[], int size, double mean)
   {
      if(size <= 1)
         return 0;
         
      double sumSq = 0;
      for(int i = 0; i < size; i++)
      {
         double diff = arr[i] - mean;
         sumSq += diff * diff;
      }
      
      return MathSqrt(sumSq / size);
   }
   
   //+------------------------------------------------------------------+
   //| Calculate Pearson correlation between two arrays                  |
   //+------------------------------------------------------------------+
   double CalculatePearsonCorrelation(const double &x[], const double &y[], int size)
   {
      if(size < 2)
         return 0;
         
      // Calculate means
      double meanX = CalculateMean(x, size);
      double meanY = CalculateMean(y, size);
      
      // Calculate covariance and standard deviations
      double sumXY = 0;
      double sumX2 = 0;
      double sumY2 = 0;
      
      for(int i = 0; i < size; i++)
      {
         double dx = x[i] - meanX;
         double dy = y[i] - meanY;
         sumXY += dx * dy;
         sumX2 += dx * dx;
         sumY2 += dy * dy;
      }
      
      // Calculate correlation
      double denominator = MathSqrt(sumX2 * sumY2);
      
      if(denominator == 0)
         return 0;
         
      double correlation = sumXY / denominator;
      
      // Clamp to valid range due to floating point errors
      return CLAMP(correlation, -1.0, 1.0);
   }
   
   //+------------------------------------------------------------------+
   //| Load historical prices for a symbol                               |
   //+------------------------------------------------------------------+
   bool LoadHistoricalPrices(int symbolIndex)
   {
      if(symbolIndex < 0 || symbolIndex >= NUM_SYMBOLS)
         return false;
         
      string symbol = m_symbols[symbolIndex];
      double prices[];
      
      // Copy close prices
      int copied = CopyClose(symbol, m_timeframe, 0, m_lookbackPeriod, prices);
      
      if(copied < m_lookbackPeriod)
      {
         Logger.Warning("Insufficient historical data for " + symbol + 
                       ". Required: " + IntegerToString(m_lookbackPeriod) +
                       ", Got: " + IntegerToString(copied));
         return false;
      }
      
      // Initialize buffer
      if(!m_priceBuffers[symbolIndex].Initialize(m_lookbackPeriod))
      {
         Logger.Error("Failed to initialize price buffer for " + symbol);
         return false;
      }
      
      // Populate buffer (prices array is oldest to newest)
      for(int i = 0; i < m_lookbackPeriod; i++)
      {
         m_priceBuffers[symbolIndex].prices[i] = prices[i];
      }
      
      m_priceBuffers[symbolIndex].head = m_lookbackPeriod - 1;
      m_priceBuffers[symbolIndex].isWarmedUp = true;
      m_priceBuffers[symbolIndex].lastUpdateTime = TimeCurrent();
      
      Logger.Info("Loaded " + IntegerToString(copied) + " historical prices for " + symbol);
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Check if new bar formed for symbol                                |
   //+------------------------------------------------------------------+
   bool IsNewBar(int symbolIndex)
   {
      datetime currentBarTime = iTime(m_symbols[symbolIndex], m_timeframe, 0);
      
      if(currentBarTime != m_lastBarTime[symbolIndex])
      {
         m_lastBarTime[symbolIndex] = currentBarTime;
         return true;
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate spread series for z-score                               |
   //+------------------------------------------------------------------+
   bool CalculateSpreadSeries(double &spreadSeries[], double &currentSpread)
   {
      if(ArrayResize(spreadSeries, m_lookbackPeriod) != m_lookbackPeriod)
         return false;
         
      // Get ordered price arrays
      double pricesAUDCAD[], pricesNZDCAD[], pricesAUDNZD[];
      
      if(!m_priceBuffers[SYMBOL_AUDCAD].GetPricesOrdered(pricesAUDCAD) ||
         !m_priceBuffers[SYMBOL_NZDCAD].GetPricesOrdered(pricesNZDCAD) ||
         !m_priceBuffers[SYMBOL_AUDNZD].GetPricesOrdered(pricesAUDNZD))
      {
         return false;
      }
      
      // Calculate spread series: (AUDCAD/NZDCAD) - AUDNZD
      for(int i = 0; i < m_lookbackPeriod; i++)
      {
         if(pricesNZDCAD[i] == 0)
         {
            spreadSeries[i] = 0;
            continue;
         }
         
         double ratio = pricesAUDCAD[i] / pricesNZDCAD[i];
         spreadSeries[i] = ratio - pricesAUDNZD[i];
      }
      
      // Current spread is the last element
      currentSpread = spreadSeries[m_lookbackPeriod - 1];
      
      return true;
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CCorrelationEngine()
   {
      m_lookbackPeriod = 250;
      m_timeframe = PERIOD_M15;
      m_updateIntervalSec = DEFAULT_CACHE_UPDATE_INTERVAL;
      m_isInitialized = false;
      m_isWarmedUp = false;
      m_lastCalculationTime = 0;
      
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         m_symbols[i] = "";
         m_lastBarTime[i] = 0;
      }
      
      m_cache.Reset();
   }
   
   //+------------------------------------------------------------------+
   //| Initialize the correlation engine                                 |
   //+------------------------------------------------------------------+
   bool Initialize(const string &symbols[], int lookbackPeriod, ENUM_TIMEFRAMES timeframe, int updateInterval = 30)
   {
      // Validate lookback period
      if(lookbackPeriod < MIN_LOOKBACK_PERIOD || lookbackPeriod > MAX_LOOKBACK_PERIOD)
      {
         Logger.Error("Invalid lookback period: " + IntegerToString(lookbackPeriod) +
                     ". Must be " + IntegerToString(MIN_LOOKBACK_PERIOD) + "-" + IntegerToString(MAX_LOOKBACK_PERIOD));
         return false;
      }
      
      m_lookbackPeriod = lookbackPeriod;
      m_timeframe = timeframe;
      m_updateIntervalSec = updateInterval;
      
      // Copy symbol names
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         m_symbols[i] = symbols[i];
      }
      
      // Load historical data for all symbols
      bool allLoaded = true;
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         if(!LoadHistoricalPrices(i))
         {
            allLoaded = false;
         }
      }
      
      if(!allLoaded)
      {
         Logger.Warning("Not all historical data loaded. Engine will warm up during trading.");
      }
      
      m_isInitialized = true;
      m_isWarmedUp = allLoaded;
      
      Logger.Info("Correlation Engine initialized - Lookback: " + IntegerToString(m_lookbackPeriod) +
                 ", Timeframe: " + EnumToString(m_timeframe));
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Update price buffers (call on each tick or new bar)               |
   //+------------------------------------------------------------------+
   void UpdatePriceBuffers()
   {
      if(!m_isInitialized)
         return;
         
      // Check for new bar on each symbol
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         if(IsNewBar(i))
         {
            // Get latest close price
            double price = iClose(m_symbols[i], m_timeframe, 1); // Previous bar close (completed)
            
            if(price > 0)
            {
               m_priceBuffers[i].AddPrice(price, TimeCurrent());
            }
         }
      }
      
      // Check if all buffers are warmed up
      if(!m_isWarmedUp)
      {
         bool allWarmedUp = true;
         for(int i = 0; i < NUM_SYMBOLS; i++)
         {
            if(!m_priceBuffers[i].isWarmedUp)
            {
               allWarmedUp = false;
               break;
            }
         }
         m_isWarmedUp = allWarmedUp;
      }
   }
   
   //+------------------------------------------------------------------+
   //| Calculate and update correlation cache                            |
   //+------------------------------------------------------------------+
   bool UpdateCorrelationCache(bool forceUpdate = false)
   {
      if(!m_isInitialized)
         return false;
         
      // Check cache freshness
      datetime currentTime = TimeCurrent();
      if(!forceUpdate && (currentTime - m_lastCalculationTime) < m_updateIntervalSec)
      {
         return m_cache.isValid;
      }
      
      // Check if warmed up
      if(!m_isWarmedUp)
      {
         m_cache.isValid = false;
         m_cache.invalidReason = "Price buffers not warmed up";
         return false;
      }
      
      // Get ordered price arrays
      double pricesAUDCAD[], pricesNZDCAD[], pricesAUDNZD[];
      
      if(!m_priceBuffers[SYMBOL_AUDCAD].GetPricesOrdered(pricesAUDCAD) ||
         !m_priceBuffers[SYMBOL_NZDCAD].GetPricesOrdered(pricesNZDCAD) ||
         !m_priceBuffers[SYMBOL_AUDNZD].GetPricesOrdered(pricesAUDNZD))
      {
         m_cache.isValid = false;
         m_cache.invalidReason = "Failed to get ordered prices";
         return false;
      }
      
      // Calculate primary correlation (AUDCAD vs NZDCAD)
      m_cache.corrAUDCAD_NZDCAD = CalculatePearsonCorrelation(pricesAUDCAD, pricesNZDCAD, m_lookbackPeriod);
      
      // Calculate secondary correlations (for validation)
      m_cache.corrAUDCAD_AUDNZD = CalculatePearsonCorrelation(pricesAUDCAD, pricesAUDNZD, m_lookbackPeriod);
      m_cache.corrNZDCAD_AUDNZD = CalculatePearsonCorrelation(pricesNZDCAD, pricesAUDNZD, m_lookbackPeriod);
      
      // Calculate synthetic ratio and spread
      double currentAUDCAD = m_priceBuffers[SYMBOL_AUDCAD].GetPrice(0);
      double currentNZDCAD = m_priceBuffers[SYMBOL_NZDCAD].GetPrice(0);
      double currentAUDNZD = m_priceBuffers[SYMBOL_AUDNZD].GetPrice(0);
      
      if(currentNZDCAD == 0)
      {
         m_cache.isValid = false;
         m_cache.invalidReason = "NZDCAD price is zero";
         return false;
      }
      
      m_cache.syntheticRatio = currentAUDCAD / currentNZDCAD;
      m_cache.actualAUDNZD = currentAUDNZD;
      m_cache.spreadValue = m_cache.syntheticRatio - currentAUDNZD;
      
      // Calculate spread z-score
      double spreadSeries[];
      double currentSpread;
      
      if(!CalculateSpreadSeries(spreadSeries, currentSpread))
      {
         m_cache.isValid = false;
         m_cache.invalidReason = "Failed to calculate spread series";
         return false;
      }
      
      m_cache.spreadMean = CalculateMean(spreadSeries, m_lookbackPeriod);
      m_cache.spreadStdDev = CalculateStdDev(spreadSeries, m_lookbackPeriod, m_cache.spreadMean);
      
      if(m_cache.spreadStdDev == 0)
      {
         m_cache.isValid = false;
         m_cache.invalidReason = "Spread standard deviation is zero";
         return false;
      }
      
      m_cache.spreadZScore = (currentSpread - m_cache.spreadMean) / m_cache.spreadStdDev;
      
      // Validate z-score
      if(!MathIsValidNumber(m_cache.spreadZScore))
      {
         m_cache.isValid = false;
         m_cache.invalidReason = "Z-score calculation resulted in invalid number";
         return false;
      }
      
      // Update metadata
      m_cache.calculationTime = currentTime;
      m_cache.lookbackPeriod = m_lookbackPeriod;
      m_cache.isValid = true;
      m_cache.invalidReason = "";
      
      m_lastCalculationTime = currentTime;
      
      Logger.LogCorrelationData(m_cache);
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Get current correlation data                                      |
   //+------------------------------------------------------------------+
   void GetCorrelationData(CorrelationData &data)
   {
      data = m_cache;
   }
   
   //+------------------------------------------------------------------+
   //| Get primary correlation coefficient                               |
   //+------------------------------------------------------------------+
   double GetPrimaryCorrelation()
   {
      return m_cache.corrAUDCAD_NZDCAD;
   }
   
   //+------------------------------------------------------------------+
   //| Get current z-score                                               |
   //+------------------------------------------------------------------+
   double GetSpreadZScore()
   {
      return m_cache.spreadZScore;
   }
   
   //+------------------------------------------------------------------+
   //| Check if engine is ready for trading                              |
   //+------------------------------------------------------------------+
   bool IsReady()
   {
      return m_isInitialized && m_isWarmedUp && m_cache.isValid;
   }
   
   //+------------------------------------------------------------------+
   //| Check if engine is warmed up                                      |
   //+------------------------------------------------------------------+
   bool IsWarmedUp()
   {
      return m_isWarmedUp;
   }
   
   //+------------------------------------------------------------------+
   //| Get current prices for all symbols                                |
   //+------------------------------------------------------------------+
   void GetCurrentPrices(double &prices[])
   {
      if(ArrayResize(prices, NUM_SYMBOLS) != NUM_SYMBOLS)
         return;
         
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         prices[i] = SymbolInfoDouble(m_symbols[i], SYMBOL_BID);
      }
   }
   
   //+------------------------------------------------------------------+
   //| Force recalculation of cache                                      |
   //+------------------------------------------------------------------+
   void ForceRecalculation()
   {
      UpdateCorrelationCache(true);
   }
};

#endif // DBASKET_CORRELATIONENGINE_MQH
//+------------------------------------------------------------------+
