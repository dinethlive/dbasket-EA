//+------------------------------------------------------------------+
//|                                        DBasket_SignalEngine.mqh  |
//|                                   D-Basket Correlation Hedging EA |
//|                                   Signal Generation Module        |
//+------------------------------------------------------------------+
#property copyright "D-Basket EA"
#property version   "1.00"
#property strict

#ifndef DBASKET_SIGNALENGINE_MQH
#define DBASKET_SIGNALENGINE_MQH

#include "DBasket_Defines.mqh"
#include "DBasket_Structures.mqh"
#include "DBasket_Logger.mqh"
#include "DBasket_CorrelationEngine.mqh"

//+------------------------------------------------------------------+
//| Signal Engine Class                                               |
//| Generates entry/exit signals with multi-stage filtering           |
//+------------------------------------------------------------------+
class CSignalEngine
{
private:
   // Configuration
   string            m_symbols[NUM_SYMBOLS];
   double            m_zScoreEntry;          // Entry threshold
   double            m_zScoreExit;           // Exit threshold
   double            m_minCorrelation;       // Minimum correlation
   double            m_maxSpreadPips;        // Maximum spread (pips)
   double            m_maxATRMultiple;       // Volatility filter
   
   // Trading hours
   int               m_startHour;
   int               m_startMinute;
   int               m_endHour;
   int               m_endMinute;
   bool              m_avoidRollover;
   
   // ATR handles for volatility calculation
   int               m_atrHandles[NUM_SYMBOLS];
   
   // State
   bool              m_isInitialized;
   int               m_signalPersistCount;   // For signal persistence filter
   ENUM_BASKET_SIGNAL m_lastSignal;          // Last detected signal
   
   //+------------------------------------------------------------------+
   //| Get current spread in pips for symbol                             |
   //+------------------------------------------------------------------+
   double GetSpreadPips(string symbol)
   {
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      
      double spread = ask - bid;
      
      // Convert to pips (handle 5-digit and 3-digit brokers)
      double pipSize = (digits == 3 || digits == 5) ? point * 10 : point;
      
      return spread / pipSize;
   }
   
   //+------------------------------------------------------------------+
   //| Check if within trading hours                                     |
   //+------------------------------------------------------------------+
   bool IsWithinTradingHours()
   {
      datetime serverTime = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(serverTime, dt);
      
      int currentMinutes = dt.hour * 60 + dt.min;
      int startMinutes = m_startHour * 60 + m_startMinute;
      int endMinutes = m_endHour * 60 + m_endMinute;
      
      // Handle case where trading window crosses midnight
      if(startMinutes <= endMinutes)
      {
         return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
      }
      else
      {
         return (currentMinutes >= startMinutes || currentMinutes <= endMinutes);
      }
   }
   
   //+------------------------------------------------------------------+
   //| Check if in rollover period (21:00-23:59 typically)               |
   //+------------------------------------------------------------------+
   bool IsRolloverPeriod()
   {
      if(!m_avoidRollover)
         return false;
         
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      
      // Rollover typically 21:00-00:10 broker time
      return (dt.hour >= 21 || (dt.hour == 0 && dt.min <= 10));
   }
   
   //+------------------------------------------------------------------+
   //| Check spread filter for all symbols                               |
   //+------------------------------------------------------------------+
   bool CheckSpreadFilter(string &failReason)
   {
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         double spreadPips = GetSpreadPips(m_symbols[i]);
         
         if(spreadPips > m_maxSpreadPips)
         {
            failReason = "Spread too high on " + m_symbols[i] + 
                        ": " + DoubleToString(spreadPips, 2) + " pips";
            return false;
         }
      }
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Check volatility filter using ATR                                 |
   //+------------------------------------------------------------------+
   bool CheckVolatilityFilter(string &failReason)
   {
      // Use AUDNZD as reference for volatility check
      if(m_atrHandles[SYMBOL_AUDNZD] == INVALID_HANDLE)
         return true; // Skip if ATR not available
         
      double atrBuffer[];
      ArraySetAsSeries(atrBuffer, true);
      
      // Get current and average ATR
      if(CopyBuffer(m_atrHandles[SYMBOL_AUDNZD], 0, 0, 20, atrBuffer) < 20)
         return true; // Skip if insufficient data
         
      double currentATR = atrBuffer[0];
      double avgATR = 0;
      for(int i = 1; i < 20; i++)
         avgATR += atrBuffer[i];
      avgATR /= 19;
      
      if(avgATR > 0 && currentATR > avgATR * m_maxATRMultiple)
      {
         failReason = "Volatility spike detected: ATR " + 
                     DoubleToString(currentATR / avgATR, 2) + "x average";
         return false;
      }
      
      return true;
   }
   
public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CSignalEngine()
   {
      m_zScoreEntry = 2.5;
      m_zScoreExit = 0.5;
      m_minCorrelation = 0.75;
      m_maxSpreadPips = 3.0;
      m_maxATRMultiple = 2.0;
      m_startHour = 0;
      m_startMinute = 0;
      m_endHour = 23;
      m_endMinute = 59;
      m_avoidRollover = true;
      m_isInitialized = false;
      m_signalPersistCount = 0;
      m_lastSignal = SIGNAL_NONE;
      
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         m_symbols[i] = "";
         m_atrHandles[i] = INVALID_HANDLE;
      }
   }
   
   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CSignalEngine()
   {
      // Release ATR handles
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
   //| Initialize signal engine                                          |
   //+------------------------------------------------------------------+
   bool Initialize(const EAConfig &config)
   {
      // Copy configuration
      for(int i = 0; i < NUM_SYMBOLS; i++)
         m_symbols[i] = config.symbols[i];
         
      m_zScoreEntry = config.zScoreEntryThreshold;
      m_zScoreExit = config.zScoreExitThreshold;
      m_minCorrelation = config.minCorrelation;
      m_maxSpreadPips = config.maxSpreadPips;
      
      m_startHour = config.tradingStartHour;
      m_startMinute = config.tradingStartMinute;
      m_endHour = config.tradingEndHour;
      m_endMinute = config.tradingEndMinute;
      m_avoidRollover = config.avoidRollover;
      
      // Create ATR handles for volatility filtering
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         m_atrHandles[i] = iATR(m_symbols[i], config.timeframe, 14);
         if(m_atrHandles[i] == INVALID_HANDLE)
         {
            Logger.Warning("Failed to create ATR handle for " + m_symbols[i]);
         }
      }
      
      m_isInitialized = true;
      
      Logger.Info("Signal Engine initialized - Entry Z: " + DoubleToString(m_zScoreEntry, 2) +
                 ", Exit Z: " + DoubleToString(m_zScoreExit, 2) +
                 ", Min Corr: " + DoubleToString(m_minCorrelation, 2));
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Check for entry signal with all filters                           |
   //+------------------------------------------------------------------+
   ENUM_BASKET_SIGNAL CheckEntrySignal(const CorrelationData &corrData, bool basketOpen, string &failReason)
   {
      failReason = "";
      
      // Stage 1: Data validity
      if(!corrData.isValid)
      {
         failReason = "Correlation data invalid: " + corrData.invalidReason;
         return SIGNAL_NONE;
      }
      
      // Stage 2: Check if basket already open
      if(basketOpen)
      {
         failReason = "Basket already open";
         return SIGNAL_NONE;
      }
      
      // Stage 3: Trading hours filter
      if(!IsWithinTradingHours())
      {
         failReason = "Outside trading hours";
         return SIGNAL_NONE;
      }
      
      // Stage 4: Rollover filter
      if(IsRolloverPeriod())
      {
         failReason = "Rollover period";
         return SIGNAL_NONE;
      }
      
      // Stage 5: Spread filter
      if(!CheckSpreadFilter(failReason))
      {
         return SIGNAL_NONE;
      }
      
      // Stage 6: Correlation stability filter
      if(corrData.corrAUDCAD_NZDCAD < m_minCorrelation)
      {
         failReason = "Correlation too low: " + DoubleToString(corrData.corrAUDCAD_NZDCAD, 4);
         return SIGNAL_NONE;
      }
      
      // Stage 7: Volatility filter
      if(!CheckVolatilityFilter(failReason))
      {
         return SIGNAL_NONE;
      }
      
      // Stage 8: Z-score threshold check
      double zScore = corrData.spreadZScore;
      
      if(MathAbs(zScore) <= m_zScoreEntry)
      {
         failReason = "Z-score below threshold: " + DoubleToString(zScore, 2);
         return SIGNAL_NONE;
      }
      
      // Determine direction
      ENUM_BASKET_SIGNAL signal = SIGNAL_NONE;
      
      if(zScore < -m_zScoreEntry)
      {
         // Negative z-score: AUDNZD underpriced relative to ratio
         // Expect AUDNZD to rise (or ratio to fall)
         signal = SIGNAL_LONG_BASKET;
         Logger.Info("LONG basket signal generated - Z-Score: " + DoubleToString(zScore, 2));
      }
      else if(zScore > m_zScoreEntry)
      {
         // Positive z-score: AUDNZD overpriced relative to ratio
         // Expect AUDNZD to fall (or ratio to rise)
         signal = SIGNAL_SHORT_BASKET;
         Logger.Info("SHORT basket signal generated - Z-Score: " + DoubleToString(zScore, 2));
      }
      
      return signal;
   }
   
   //+------------------------------------------------------------------+
   //| Check for exit signal                                             |
   //+------------------------------------------------------------------+
   bool CheckExitSignal(const CorrelationData &corrData, const BasketState &basket, 
                        double takeProfitAmount, double stopLossAmount, 
                        int maxHoldingHours, ENUM_EXIT_REASON &exitReason)
   {
      exitReason = EXIT_MANUAL;
      
      // Check if basket is active
      if(!basket.IsActive())
         return false;
         
      // Exit 1: Mean reversion (z-score returned to near zero)
      if(corrData.isValid)
      {
         double currentZ = corrData.spreadZScore;
         
         // For long basket, we entered when z < -entry, exit when z > -exit
         // For short basket, we entered when z > +entry, exit when z < +exit
         if(basket.direction == SIGNAL_LONG_BASKET && currentZ > -m_zScoreExit)
         {
            exitReason = EXIT_MEAN_REVERSION;
            Logger.Info("Exit signal: Mean reversion (Z: " + DoubleToString(currentZ, 2) + ")");
            return true;
         }
         else if(basket.direction == SIGNAL_SHORT_BASKET && currentZ < m_zScoreExit)
         {
            exitReason = EXIT_MEAN_REVERSION;
            Logger.Info("Exit signal: Mean reversion (Z: " + DoubleToString(currentZ, 2) + ")");
            return true;
         }
      }
      
      // Exit 2: Take profit
      if(takeProfitAmount > 0 && basket.unrealizedPL >= takeProfitAmount)
      {
         exitReason = EXIT_TAKE_PROFIT;
         Logger.Info("Exit signal: Take profit reached (" + DoubleToString(basket.unrealizedPL, 2) + ")");
         return true;
      }
      
      // Exit 3: Stop loss
      if(stopLossAmount > 0 && basket.unrealizedPL <= -stopLossAmount)
      {
         exitReason = EXIT_STOP_LOSS;
         Logger.Warning("Exit signal: Stop loss triggered (" + DoubleToString(basket.unrealizedPL, 2) + ")");
         return true;
      }
      
      // Exit 4: Maximum holding time
      if(maxHoldingHours > 0)
      {
         int holdingSeconds = (int)(TimeCurrent() - basket.openTime);
         int holdingHours = holdingSeconds / 3600;
         
         if(holdingHours >= maxHoldingHours)
         {
            exitReason = EXIT_MAX_TIME;
            Logger.Info("Exit signal: Max holding time (" + IntegerToString(holdingHours) + " hours)");
            return true;
         }
      }
      
      // Exit 5: Correlation breakdown
      if(corrData.isValid && corrData.corrAUDCAD_NZDCAD < 0.5)
      {
         exitReason = EXIT_CORRELATION_BREAK;
         Logger.Warning("Exit signal: Correlation breakdown (" + DoubleToString(corrData.corrAUDCAD_NZDCAD, 4) + ")");
         return true;
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Get current spread summary                                        |
   //+------------------------------------------------------------------+
   double GetTotalSpreadPips()
   {
      double total = 0;
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         total += GetSpreadPips(m_symbols[i]);
      }
      return total;
   }
   
   //+------------------------------------------------------------------+
   //| Check if trading is allowed (time and conditions)                 |
   //+------------------------------------------------------------------+
   bool IsTradingAllowed()
   {
      return IsWithinTradingHours() && !IsRolloverPeriod();
   }
   
   //+------------------------------------------------------------------+
   //| Update configuration                                              |
   //+------------------------------------------------------------------+
   void UpdateConfig(double zScoreEntry, double zScoreExit, double minCorrelation, double maxSpread)
   {
      m_zScoreEntry = zScoreEntry;
      m_zScoreExit = zScoreExit;
      m_minCorrelation = minCorrelation;
      m_maxSpreadPips = maxSpread;
   }
};

#endif // DBASKET_SIGNALENGINE_MQH
//+------------------------------------------------------------------+
