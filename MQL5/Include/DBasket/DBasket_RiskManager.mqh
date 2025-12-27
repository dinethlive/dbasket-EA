//+------------------------------------------------------------------+
//|                                        DBasket_RiskManager.mqh   |
//|                                   D-Basket Correlation Hedging EA |
//|                                   Risk Management Module          |
//+------------------------------------------------------------------+
#property copyright "D-Basket EA"
#property version   "1.00"
#property strict

#ifndef DBASKET_RISKMANAGER_MQH
#define DBASKET_RISKMANAGER_MQH

#include "DBasket_Defines.mqh"
#include "DBasket_Structures.mqh"
#include "DBasket_Logger.mqh"

//+------------------------------------------------------------------+
//| Risk Manager Class                                                |
//| Monitors and enforces risk limits with circuit breaker            |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   // Configuration
   double            m_maxDrawdownPercent;
   double            m_warningDrawdownPercent;
   double            m_maxDailyLossAmount;
   double            m_maxDailyLossPercent;
   double            m_minMarginLevel;
   double            m_warningMarginLevel;
   int               m_maxConsecutiveLosses;
   
   // State tracking
   PerformanceMetrics m_metrics;
   ENUM_CIRCUIT_BREAKER_STATE m_cbState;
   string            m_cbTripReason;
   datetime          m_cbTripTime;
   
   // Daily tracking
   datetime          m_lastDailyReset;
   double            m_dailyStartEquity;
   double            m_dailyRealizedPL;
   int               m_consecutiveLosses;
   
   // Historical high
   double            m_peakEquity;
   double            m_startingBalance;
   
   bool              m_isInitialized;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CRiskManager()
   {
      m_maxDrawdownPercent = DEFAULT_MAX_DRAWDOWN_PERCENT;
      m_warningDrawdownPercent = CB_WARNING_DRAWDOWN_PERCENT;
      m_maxDailyLossAmount = DEFAULT_DAILY_LOSS_LIMIT;
      m_maxDailyLossPercent = 5.0;
      m_minMarginLevel = DEFAULT_MIN_MARGIN_LEVEL;
      m_warningMarginLevel = DEFAULT_WARNING_MARGIN_LEVEL;
      m_maxConsecutiveLosses = CB_MAX_CONSECUTIVE_LOSSES;
      
      m_cbState = CB_NORMAL;
      m_cbTripReason = "";
      m_cbTripTime = 0;
      
      m_lastDailyReset = 0;
      m_dailyStartEquity = 0;
      m_dailyRealizedPL = 0;
      m_consecutiveLosses = 0;
      
      m_peakEquity = 0;
      m_startingBalance = 0;
      
      m_isInitialized = false;
      m_metrics.Reset();
   }
   
   //+------------------------------------------------------------------+
   //| Initialize risk manager                                           |
   //+------------------------------------------------------------------+
   bool Initialize(const EAConfig &config)
   {
      m_maxDrawdownPercent = config.maxDrawdownPercent;
      m_warningDrawdownPercent = m_maxDrawdownPercent * 0.6; // 60% of max
      m_maxDailyLossAmount = config.maxDailyLossAmount;
      m_maxDailyLossPercent = config.maxDailyLossPercent;
      
      // Initialize tracking
      m_startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_dailyStartEquity = m_peakEquity;
      m_lastDailyReset = TimeCurrent();
      
      m_metrics.Reset();
      m_metrics.startingBalance = m_startingBalance;
      m_metrics.peakEquity = m_peakEquity;
      m_metrics.metricsStartTime = TimeCurrent();
      m_metrics.dailyStartEquity = m_dailyStartEquity;
      m_metrics.dailyResetTime = m_lastDailyReset;
      
      m_cbState = CB_NORMAL;
      m_isInitialized = true;
      
      Logger.Info("Risk Manager initialized - Max DD: " + DoubleToString(m_maxDrawdownPercent, 1) + 
                 "%, Daily Limit: $" + DoubleToString(m_maxDailyLossAmount, 2));
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Update metrics (call every tick or periodically)                  |
   //+------------------------------------------------------------------+
   void UpdateMetrics()
   {
      if(!m_isInitialized)
         return;
         
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      
      // Update peak equity
      if(currentEquity > m_peakEquity)
         m_peakEquity = currentEquity;
      
      // Calculate current drawdown
      double drawdown = 0;
      if(m_peakEquity > 0)
         drawdown = ((m_peakEquity - currentEquity) / m_peakEquity) * 100;
      
      // Check for daily reset
      CheckDailyReset();
      
      // Update metrics structure
      m_metrics.currentEquity = currentEquity;
      m_metrics.currentBalance = currentBalance;
      m_metrics.peakEquity = m_peakEquity;
      m_metrics.currentDrawdownPercent = drawdown;
      m_metrics.dailyPnL = currentEquity - m_dailyStartEquity;
      m_metrics.uptimeSeconds = (int)(TimeCurrent() - m_metrics.metricsStartTime);
      
      if(drawdown > m_metrics.maxDrawdownPercent)
      {
         m_metrics.maxDrawdownPercent = drawdown;
         m_metrics.maxDrawdownValue = m_peakEquity - currentEquity;
      }
      
      // Update win rate
      if(m_metrics.closedBaskets > 0)
         m_metrics.winRate = (double)m_metrics.winningBaskets / m_metrics.closedBaskets;
   }
   
   //+------------------------------------------------------------------+
   //| Check for daily reset                                             |
   //+------------------------------------------------------------------+
   void CheckDailyReset()
   {
      MqlDateTime dtNow, dtLast;
      TimeToStruct(TimeCurrent(), dtNow);
      TimeToStruct(m_lastDailyReset, dtLast);
      
      // Check if day changed
      if(dtNow.day != dtLast.day || dtNow.mon != dtLast.mon || dtNow.year != dtLast.year)
      {
         // New trading day
         m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         m_dailyRealizedPL = 0;
         m_lastDailyReset = TimeCurrent();
         
         m_metrics.dailyStartEquity = m_dailyStartEquity;
         m_metrics.dailyResetTime = m_lastDailyReset;
         m_metrics.dailyPnL = 0;
         
         Logger.Info("Daily reset - New equity baseline: " + DoubleToString(m_dailyStartEquity, 2));
         
         // Reset circuit breaker if tripped due to daily limits or consecutive losses
         if(m_cbState == CB_TRIPPED)
         {
            if(m_cbTripReason == "Daily loss limit exceeded" || 
               StringFind(m_cbTripReason, "Maximum consecutive losses") >= 0)
            {
               Logger.Info("Resetting circuit breaker after daily reset");
               ResetCircuitBreaker();
            }
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Check all risk limits                                             |
   //+------------------------------------------------------------------+
   bool CheckRiskLimits(string &failReason)
   {
      failReason = "";
      
      if(!m_isInitialized)
         return true;
         
      // Update metrics first
      UpdateMetrics();
      
      // If already tripped, stay tripped
      if(m_cbState == CB_TRIPPED)
      {
         failReason = "Circuit breaker tripped: " + m_cbTripReason;
         return false;
      }
      
      ENUM_CIRCUIT_BREAKER_STATE newState = CB_NORMAL;
      string reason = "";
      
      // Check 1: Drawdown limit
      if(m_metrics.currentDrawdownPercent >= m_maxDrawdownPercent)
      {
         reason = "Maximum drawdown exceeded: " + DoubleToString(m_metrics.currentDrawdownPercent, 2) + "%";
         newState = CB_TRIPPED;
      }
      else if(m_metrics.currentDrawdownPercent >= m_warningDrawdownPercent)
      {
         reason = "Approaching drawdown limit: " + DoubleToString(m_metrics.currentDrawdownPercent, 2) + "%";
         if(newState < CB_WARNING)
            newState = CB_WARNING;
      }
      
      // Check 2: Daily loss limit
      if(m_metrics.dailyPnL <= -m_maxDailyLossAmount)
      {
         reason = "Daily loss limit exceeded: $" + DoubleToString(MathAbs(m_metrics.dailyPnL), 2);
         newState = CB_TRIPPED;
      }
      else if(m_maxDailyLossPercent > 0)
      {
         double dailyLossPercent = MathAbs(m_metrics.dailyPnL) / m_dailyStartEquity * 100;
         if(m_metrics.dailyPnL < 0 && dailyLossPercent >= m_maxDailyLossPercent)
         {
            reason = "Daily loss % exceeded: " + DoubleToString(dailyLossPercent, 2) + "%";
            newState = CB_TRIPPED;
         }
      }
      
      // Check 3: Margin level
      double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(marginLevel > 0) // 0 means no positions
      {
         if(marginLevel < m_minMarginLevel)
         {
            reason = "Margin level critical: " + DoubleToString(marginLevel, 0) + "%";
            newState = CB_TRIPPED;
         }
         else if(marginLevel < m_warningMarginLevel)
         {
            if(reason == "")
               reason = "Margin level warning: " + DoubleToString(marginLevel, 0) + "%";
            if(newState < CB_WARNING)
               newState = CB_WARNING;
         }
      }
      
      // Check 4: Consecutive losses
      if(m_consecutiveLosses >= m_maxConsecutiveLosses)
      {
         reason = "Maximum consecutive losses: " + IntegerToString(m_consecutiveLosses);
         newState = CB_TRIPPED;
      }
      
      // Apply state change
      if(newState > m_cbState)
      {
         m_cbState = newState;
         
         if(newState == CB_TRIPPED)
         {
            m_cbTripReason = reason;
            m_cbTripTime = TimeCurrent();
            Logger.Error("CIRCUIT BREAKER TRIPPED: " + reason);
         }
         else if(newState == CB_WARNING)
         {
            Logger.Warning("RISK WARNING: " + reason);
         }
      }
      
      failReason = reason;
      return (m_cbState != CB_TRIPPED);
   }
   
   //+------------------------------------------------------------------+
   //| Record a basket close result                                      |
   //+------------------------------------------------------------------+
   void RecordBasketClose(double pl, bool isWin)
   {
      m_metrics.closedBaskets++;
      m_dailyRealizedPL += pl;
      m_metrics.realizedPL += pl;
      
      if(isWin)
      {
         m_metrics.winningBaskets++;
         m_consecutiveLosses = 0;
      }
      else
      {
         m_metrics.losingBaskets++;
         m_consecutiveLosses++;
         
         if(m_consecutiveLosses > m_metrics.maxConsecutiveLosses)
            m_metrics.maxConsecutiveLosses = m_consecutiveLosses;
      }
      
      m_metrics.consecutiveLosses = m_consecutiveLosses;
      
      // Update win rate
      if(m_metrics.closedBaskets > 0)
         m_metrics.winRate = (double)m_metrics.winningBaskets / m_metrics.closedBaskets;
      
      // Calculate profit factor
      double totalWins = 0, totalLosses = 0;
      // (Would need to track these separately for accurate profit factor)
      
      Logger.Debug("Basket recorded - P/L: $" + DoubleToString(pl, 2) +
                  ", Win Rate: " + DoubleToString(m_metrics.winRate * 100, 1) + "%" +
                  ", Consecutive Losses: " + IntegerToString(m_consecutiveLosses));
   }
   
   //+------------------------------------------------------------------+
   //| Record basket open                                                |
   //+------------------------------------------------------------------+
   void RecordBasketOpen()
   {
      m_metrics.totalBaskets++;
      m_metrics.executedSignals++;
      m_metrics.lastTradeTime = TimeCurrent();
   }
   
   //+------------------------------------------------------------------+
   //| Record signal generation                                          |
   //+------------------------------------------------------------------+
   void RecordSignal(bool executed)
   {
      m_metrics.totalSignals++;
      if(!executed)
         m_metrics.filteredSignals++;
   }
   
   //+------------------------------------------------------------------+
   //| Check if trading is allowed                                       |
   //+------------------------------------------------------------------+
   bool IsTradingAllowed()
   {
      return (m_cbState != CB_TRIPPED);
   }
   
   //+------------------------------------------------------------------+
   //| Get circuit breaker state                                         |
   //+------------------------------------------------------------------+
   ENUM_CIRCUIT_BREAKER_STATE GetCircuitBreakerState()
   {
      return m_cbState;
   }
   
   //+------------------------------------------------------------------+
   //| Reset circuit breaker (manual reset)                              |
   //+------------------------------------------------------------------+
   void ResetCircuitBreaker()
   {
      if(m_cbState == CB_TRIPPED)
      {
         Logger.Info("Circuit breaker reset - Previous reason: " + m_cbTripReason);
         m_cbState = CB_NORMAL;
         m_cbTripReason = "";
         m_cbTripTime = 0;
         m_consecutiveLosses = 0;
      }
   }
   
   //+------------------------------------------------------------------+
   //| Get performance metrics                                           |
   //+------------------------------------------------------------------+
   void GetMetrics(PerformanceMetrics &metrics)
   {
      metrics = m_metrics;
   }
   
   //+------------------------------------------------------------------+
   //| Get current drawdown                                              |
   //+------------------------------------------------------------------+
   double GetCurrentDrawdown()
   {
      return m_metrics.currentDrawdownPercent;
   }
   
   //+------------------------------------------------------------------+
   //| Get daily P&L                                                     |
   //+------------------------------------------------------------------+
   double GetDailyPnL()
   {
      return m_metrics.dailyPnL;
   }
   
   //+------------------------------------------------------------------+
   //| Check emergency exit conditions                                   |
   //+------------------------------------------------------------------+
   bool CheckEmergencyExit(string &reason)
   {
      reason = "";
      
      // Check margin level emergency
      double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(marginLevel > 0 && marginLevel < 150) // Very critical
      {
         reason = "Emergency: Margin call imminent (" + DoubleToString(marginLevel, 0) + "%)";
         return true;
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Display metrics on chart                                          |
   //+------------------------------------------------------------------+
   void DisplayMetricsOnChart()
   {
      string status = (m_cbState == CB_TRIPPED) ? "HALTED" : 
                     (m_cbState == CB_WARNING) ? "WARNING" : "NORMAL";
      
      string display = StringFormat(
         "=== D-Basket EA Risk Monitor ===\n" +
         "Status: %s\n" +
         "Net P/L: $%.2f (%.1f%%)\n" +
         "Daily P/L: $%.2f\n" +
         "Drawdown: %.2f%% (Max: %.2f%%)\n" +
         "Baskets: %d | Win Rate: %.1f%%\n" +
         "Consecutive Losses: %d",
         status,
         m_metrics.currentEquity - m_startingBalance,
         ((m_metrics.currentEquity - m_startingBalance) / m_startingBalance) * 100,
         m_metrics.dailyPnL,
         m_metrics.currentDrawdownPercent,
         m_metrics.maxDrawdownPercent,
         m_metrics.closedBaskets,
         m_metrics.winRate * 100,
         m_consecutiveLosses
      );
      
      Comment(display);
   }
};

#endif // DBASKET_RISKMANAGER_MQH
//+------------------------------------------------------------------+
