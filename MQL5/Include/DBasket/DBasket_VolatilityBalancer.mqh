//+------------------------------------------------------------------+
//|                                   DBasket_VolatilityBalancer.mqh |
//|                                D-Basket Correlation Hedging EA   |
//|                                ATR-Based Position Sizing         |
//+------------------------------------------------------------------+
#property copyright "D-Basket EA"
#property version   "2.00"
#property strict

#ifndef DBASKET_VOLATILITYBALANCER_MQH
#define DBASKET_VOLATILITYBALANCER_MQH

#include "DBasket_Defines.mqh"
#include "DBasket_Structures.mqh"
#include "DBasket_Logger.mqh"

//+------------------------------------------------------------------+
//| Volatility Data Structure                                         |
//+------------------------------------------------------------------+
struct VolatilityData
{
   double            atr[NUM_SYMBOLS];       // ATR values for each symbol
   double            weights[NUM_SYMBOLS];   // Inverse volatility weights
   double            adjustedLots[NUM_SYMBOLS]; // Final lot sizes
   datetime          lastUpdateTime;         // Timestamp of last calculation
   bool              isValid;                // True if calculation succeeded
   
   void Reset()
   {
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         atr[i] = 0;
         weights[i] = 0.333333;  // Default equal weight
         adjustedLots[i] = 0.01;
      }
      lastUpdateTime = 0;
      isValid = false;
   }
};

//+------------------------------------------------------------------+
//| Volatility Balancer Class                                         |
//| Risk Parity Position Sizing via ATR                               |
//+------------------------------------------------------------------+
class CVolatilityBalancer
{
private:
   // Configuration
   string            m_symbols[NUM_SYMBOLS];
   int               m_atrPeriod;           // ATR lookback period
   int               m_atrHandles[NUM_SYMBOLS]; // ATR indicator handles
   double            m_minWeight;           // Minimum weight per symbol
   double            m_maxWeight;           // Maximum weight per symbol
   bool              m_enabled;             // ATR sizing enabled
   
   // State
   VolatilityData    m_cache;
   int               m_barsSinceUpdate;
   bool              m_isInitialized;
   
   //+------------------------------------------------------------------+
   //| Normalize lot size to broker requirements                        |
   //+------------------------------------------------------------------+
   double NormalizeLots(string symbol, double lots)
   {
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      
      if(lotStep == 0) lotStep = 0.01;
      if(minLot == 0) minLot = 0.01;
      if(maxLot == 0) maxLot = 100.0;
      
      // Round to lot step
      lots = MathFloor(lots / lotStep) * lotStep;
      
      // Clamp to min/max
      lots = MathMax(minLot, MathMin(lots, maxLot));
      
      return NormalizeDouble(lots, 2);
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CVolatilityBalancer()
   {
      m_atrPeriod = 14;
      m_minWeight = 0.15;
      m_maxWeight = 0.50;
      m_enabled = true;
      m_barsSinceUpdate = 999;
      m_isInitialized = false;
      
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         m_symbols[i] = "";
         m_atrHandles[i] = INVALID_HANDLE;
      }
      
      m_cache.Reset();
   }
   
   //+------------------------------------------------------------------+
   //| Destructor - Release indicator handles                            |
   //+------------------------------------------------------------------+
   ~CVolatilityBalancer()
   {
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         if(m_atrHandles[i] != INVALID_HANDLE)
         {
            IndicatorRelease(m_atrHandles[i]);
            m_atrHandles[i] = INVALID_HANDLE;
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Initialize volatility balancer                                    |
   //+------------------------------------------------------------------+
   bool Initialize(const string &symbols[], int atrPeriod, 
                   double minWeight, double maxWeight, bool enabled)
   {
      m_atrPeriod = atrPeriod;
      m_minWeight = minWeight;
      m_maxWeight = maxWeight;
      m_enabled = enabled;
      
      // Copy symbols
      for(int i = 0; i < NUM_SYMBOLS; i++)
         m_symbols[i] = symbols[i];
      
      // Create ATR indicator handles
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         m_atrHandles[i] = iATR(m_symbols[i], PERIOD_CURRENT, m_atrPeriod);
         if(m_atrHandles[i] == INVALID_HANDLE)
         {
            Logger.Error("Failed to create ATR handle for " + m_symbols[i]);
            return false;
         }
      }
      
      m_isInitialized = true;
      m_cache.Reset();
      m_barsSinceUpdate = 999;
      
      Logger.Info("Volatility Balancer initialized - ATR Period: " + IntegerToString(m_atrPeriod) +
                 ", Enabled: " + (m_enabled ? "Yes" : "No"));
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Update ATR values and calculate weights                           |
   //+------------------------------------------------------------------+
   bool Update(bool forceUpdate = false)
   {
      if(!m_isInitialized)
      {
         Logger.Error("Volatility Balancer not initialized");
         return false;
      }
      
      // Check if update needed
      m_barsSinceUpdate++;
      if(!forceUpdate && m_barsSinceUpdate < 1 && m_cache.isValid)
      {
         return true;  // Use cached values
      }
      
      m_barsSinceUpdate = 0;
      
      // Get ATR values for each symbol
      double totalATR = 0;
      double totalInvATR = 0;
      
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         double buffer[1];
         if(CopyBuffer(m_atrHandles[i], 0, 0, 1, buffer) != 1)
         {
            Logger.Warning("Failed to get ATR for " + m_symbols[i] + ", using cached value");
            if(m_cache.atr[i] <= 0)
            {
               m_cache.isValid = false;
               return false;
            }
            // Use cached ATR
         }
         else
         {
            m_cache.atr[i] = buffer[0];
         }
         
         if(m_cache.atr[i] <= 0)
         {
            Logger.Error("Invalid ATR value for " + m_symbols[i]);
            m_cache.isValid = false;
            return false;
         }
         
         totalATR += m_cache.atr[i];
         totalInvATR += 1.0 / m_cache.atr[i];
      }
      
      // Calculate inverse volatility weights
      // Higher volatility = smaller weight
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         double rawWeight = (1.0 / m_cache.atr[i]) / totalInvATR;
         
         // Apply min/max constraints
         rawWeight = MathMax(m_minWeight, MathMin(rawWeight, m_maxWeight));
         
         m_cache.weights[i] = rawWeight;
      }
      
      // Renormalize weights to sum to 1.0
      double totalWeight = 0;
      for(int i = 0; i < NUM_SYMBOLS; i++)
         totalWeight += m_cache.weights[i];
         
      if(totalWeight > 0)
      {
         for(int i = 0; i < NUM_SYMBOLS; i++)
            m_cache.weights[i] /= totalWeight;
      }
      
      m_cache.lastUpdateTime = TimeCurrent();
      m_cache.isValid = true;
      
      Logger.Debug("ATR Weights updated: AUDCAD=" + DoubleToString(m_cache.weights[SYMBOL_AUDCAD], 3) +
                  ", NZDCAD=" + DoubleToString(m_cache.weights[SYMBOL_NZDCAD], 3) +
                  ", AUDNZD=" + DoubleToString(m_cache.weights[SYMBOL_AUDNZD], 3));
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate weighted lot sizes                                      |
   //| baseLots: total lot budget                                        |
   //| lots[]: output array with adjusted lot sizes                      |
   //+------------------------------------------------------------------+
   bool CalculateWeightedLots(double baseLots, double &lots[])
   {
      if(ArraySize(lots) < NUM_SYMBOLS)
         ArrayResize(lots, NUM_SYMBOLS);
      
      if(!m_enabled || !m_cache.isValid)
      {
         // Fallback to equal sizing
         for(int i = 0; i < NUM_SYMBOLS; i++)
         {
            lots[i] = NormalizeLots(m_symbols[i], baseLots);
         }
         return true;
      }
      
      // Apply weights to base lots
      // Multiply by 3 because weights sum to 1.0 but we want 3 positions
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         double rawLots = baseLots * m_cache.weights[i] * 3.0;
         lots[i] = NormalizeLots(m_symbols[i], rawLots);
         m_cache.adjustedLots[i] = lots[i];
      }
      
      Logger.Debug("Weighted lots: AUDCAD=" + DoubleToString(lots[SYMBOL_AUDCAD], 2) +
                  ", NZDCAD=" + DoubleToString(lots[SYMBOL_NZDCAD], 2) +
                  ", AUDNZD=" + DoubleToString(lots[SYMBOL_AUDNZD], 2));
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Get weight for a specific symbol                                  |
   //+------------------------------------------------------------------+
   double GetWeight(int symbolIndex)
   {
      if(symbolIndex < 0 || symbolIndex >= NUM_SYMBOLS)
         return 0.333333;
      return m_cache.weights[symbolIndex];
   }
   
   //+------------------------------------------------------------------+
   //| Get ATR for a specific symbol                                     |
   //+------------------------------------------------------------------+
   double GetATR(int symbolIndex)
   {
      if(symbolIndex < 0 || symbolIndex >= NUM_SYMBOLS)
         return 0;
      return m_cache.atr[symbolIndex];
   }
   
   //+------------------------------------------------------------------+
   //| Get cached volatility data                                        |
   //+------------------------------------------------------------------+
   void GetData(VolatilityData &data)
   {
      data = m_cache;
   }
   
   //+------------------------------------------------------------------+
   //| Is enabled                                                        |
   //+------------------------------------------------------------------+
   bool IsEnabled()
   {
      return m_enabled;
   }
   
   //+------------------------------------------------------------------+
   //| Is cache valid                                                    |
   //+------------------------------------------------------------------+
   bool IsValid()
   {
      return m_cache.isValid;
   }
   
   //+------------------------------------------------------------------+
   //| Enable/disable volatility balancing                               |
   //+------------------------------------------------------------------+
   void SetEnabled(bool enabled)
   {
      m_enabled = enabled;
   }
};

#endif // DBASKET_VOLATILITYBALANCER_MQH
//+------------------------------------------------------------------+
