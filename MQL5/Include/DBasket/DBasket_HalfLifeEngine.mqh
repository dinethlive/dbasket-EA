//+------------------------------------------------------------------+
//|                                      DBasket_HalfLifeEngine.mqh  |
//|                                D-Basket Correlation Hedging EA   |
//|                                Ornstein-Uhlenbeck Half-Life      |
//+------------------------------------------------------------------+
#property copyright "D-Basket EA"
#property version   "2.00"
#property strict

#ifndef DBASKET_HALFLIFEENGINE_MQH
#define DBASKET_HALFLIFEENGINE_MQH

#include "DBasket_Defines.mqh"
#include "DBasket_Structures.mqh"
#include "DBasket_Logger.mqh"

//+------------------------------------------------------------------+
//| Half-Life Data Structure                                          |
//+------------------------------------------------------------------+
struct HalfLifeData
{
   double            lambda;              // AR(1) coefficient (must be < 0)
   double            alpha;               // Intercept
   double            halfLife;            // Calculated half-life in bars
   double            sigma;               // Residual standard deviation
   double            ouVariance;          // Long-term O-U variance
   datetime          lastUpdateTime;      // Timestamp of last calculation
   bool              isValid;             // True if lambda < 0 (mean-reverting)
   bool              isMeanReverting;     // True if spread is mean-reverting
   string            invalidReason;       // Description if invalid
   
   void Reset()
   {
      lambda = 0;
      alpha = 0;
      halfLife = 100;  // Default fallback
      sigma = 0;
      ouVariance = 0;
      lastUpdateTime = 0;
      isValid = false;
      isMeanReverting = false;
      invalidReason = "";
   }
};

//+------------------------------------------------------------------+
//| Half-Life Engine Class                                            |
//| Estimates mean reversion speed via AR(1) regression               |
//+------------------------------------------------------------------+
class CHalfLifeEngine
{
private:
   // Configuration
   int               m_lookbackPeriod;     // Bars for regression
   int               m_updateIntervalBars; // Bars between updates
   int               m_minHalfLife;        // Minimum acceptable half-life
   int               m_maxHalfLife;        // Maximum acceptable half-life
   double            m_exitMultiplier;     // Max holding = multiplier * halfLife
   double            m_stopLossSigma;      // Stop loss distance in sigma
   
   // State
   HalfLifeData      m_cache;
   int               m_barsSinceUpdate;
   bool              m_isInitialized;
   
   //+------------------------------------------------------------------+
   //| Calculate mean of array                                          |
   //+------------------------------------------------------------------+
   double ArrayMean(const double &arr[], int count)
   {
      if(count <= 0) return 0;
      double sum = 0;
      for(int i = 0; i < count; i++)
         sum += arr[i];
      return sum / count;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate standard deviation of array                            |
   //+------------------------------------------------------------------+
   double ArrayStdDev(const double &arr[], int count, double mean)
   {
      if(count <= 1) return 0;
      double sumSq = 0;
      for(int i = 0; i < count; i++)
      {
         double diff = arr[i] - mean;
         sumSq += diff * diff;
      }
      return MathSqrt(sumSq / (count - 1));
   }
   
   //+------------------------------------------------------------------+
   //| AR(1) Regression: delta_y = alpha + lambda * y_lag + epsilon     |
   //| Tests for mean reversion in spread series                        |
   //+------------------------------------------------------------------+
   bool AR1Regression(const double &spread[], int count,
                      double &lambda, double &alpha, double &sigma)
   {
      if(count < 50)
      {
         Logger.Warning("AR1: Insufficient data points: " + IntegerToString(count));
         return false;
      }
      
      int n = count - 1;  // Number of differences
      
      // Construct arrays
      double y_lag[];
      double delta_y[];
      
      if(ArrayResize(y_lag, n) != n || ArrayResize(delta_y, n) != n)
         return false;
      
      for(int i = 0; i < n; i++)
      {
         y_lag[i] = spread[i];
         delta_y[i] = spread[i + 1] - spread[i];
      }
      
      // Calculate means
      double meanYLag = ArrayMean(y_lag, n);
      double meanDeltaY = ArrayMean(delta_y, n);
      
      // Calculate covariance and variance
      double covYD = 0;
      double varYLag = 0;
      
      for(int i = 0; i < n; i++)
      {
         double dy_lag = y_lag[i] - meanYLag;
         double dy = delta_y[i] - meanDeltaY;
         covYD += dy_lag * dy;
         varYLag += dy_lag * dy_lag;
      }
      
      if(MathAbs(varYLag) < 0.0000001)
      {
         Logger.Warning("AR1: Near-zero variance in lagged series");
         return false;
      }
      
      // Lambda coefficient
      lambda = covYD / varYLag;
      alpha = meanDeltaY - lambda * meanYLag;
      
      // Calculate residuals for sigma estimation
      double residualSumSq = 0;
      for(int i = 0; i < n; i++)
      {
         double fitted = alpha + lambda * y_lag[i];
         double resid = delta_y[i] - fitted;
         residualSumSq += resid * resid;
      }
      
      sigma = MathSqrt(residualSumSq / (n - 2));
      
      return true;
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CHalfLifeEngine()
   {
      m_lookbackPeriod = 250;
      m_updateIntervalBars = 20;
      m_minHalfLife = 10;
      m_maxHalfLife = 500;
      m_exitMultiplier = 2.0;
      m_stopLossSigma = 1.5;
      m_barsSinceUpdate = 999;  // Force initial calculation
      m_isInitialized = false;
      m_cache.Reset();
   }
   
   //+------------------------------------------------------------------+
   //| Initialize engine                                                 |
   //+------------------------------------------------------------------+
   bool Initialize(int lookbackPeriod, int updateIntervalBars, 
                   int minHalfLife, int maxHalfLife,
                   double exitMultiplier, double stopLossSigma)
   {
      if(lookbackPeriod < 50)
      {
         Logger.Error("HalfLife: Lookback period too short (min 50)");
         return false;
      }
      
      m_lookbackPeriod = lookbackPeriod;
      m_updateIntervalBars = updateIntervalBars;
      m_minHalfLife = minHalfLife;
      m_maxHalfLife = maxHalfLife;
      m_exitMultiplier = exitMultiplier;
      m_stopLossSigma = stopLossSigma;
      m_barsSinceUpdate = 999;
      m_isInitialized = true;
      m_cache.Reset();
      
      Logger.Info("Half-Life Engine initialized - Lookback: " + IntegerToString(m_lookbackPeriod) +
                 ", Exit Multiplier: " + DoubleToString(m_exitMultiplier, 1) +
                 ", SL Sigma: " + DoubleToString(m_stopLossSigma, 1));
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Update half-life calculation                                      |
   //| spread[] = spread series (AUDNZD - syntheticRatio)                |
   //+------------------------------------------------------------------+
   bool Update(const double &spread[], int dataCount, bool forceUpdate = false)
   {
      if(!m_isInitialized)
      {
         Logger.Error("Half-Life Engine not initialized");
         return false;
      }
      
      // Check if update needed
      m_barsSinceUpdate++;
      if(!forceUpdate && m_barsSinceUpdate < m_updateIntervalBars && m_cache.isValid)
      {
         return true;  // Use cached values
      }
      
      // Validate data
      int count = MathMin(dataCount, m_lookbackPeriod);
      if(count < 50)
      {
         m_cache.isValid = false;
         m_cache.invalidReason = "Insufficient data: " + IntegerToString(count);
         return false;
      }
      
      // Reset update counter
      m_barsSinceUpdate = 0;
      
      // Run AR(1) regression
      double lambda, alpha, sigma;
      
      if(!AR1Regression(spread, count, lambda, alpha, sigma))
      {
         m_cache.isValid = false;
         m_cache.invalidReason = "AR(1) regression failed";
         return false;
      }
      
      // Check if mean-reverting (lambda must be negative)
      if(lambda >= 0 || lambda > -0.001)
      {
         m_cache.isValid = true;
         m_cache.isMeanReverting = false;
         m_cache.lambda = lambda;
         m_cache.halfLife = 9999;  // Very long (no reversion)
         m_cache.invalidReason = "Non-mean-reverting (lambda >= 0)";
         
         Logger.Debug("HalfLife: Spread is non-mean-reverting, lambda = " + 
                     DoubleToString(lambda, 6));
         return true;
      }
      
      // Calculate half-life: tau = -ln(2) / lambda
      double halfLife = -MathLog(2.0) / lambda;
      
      // Calculate O-U variance: sigma^2 / (-2 * lambda)
      double ouVariance = (sigma * sigma) / (-2.0 * lambda);
      
      // Validate half-life range
      bool isReasonable = (halfLife >= m_minHalfLife && halfLife <= m_maxHalfLife);
      
      // Update cache
      m_cache.lambda = lambda;
      m_cache.alpha = alpha;
      m_cache.halfLife = halfLife;
      m_cache.sigma = sigma;
      m_cache.ouVariance = ouVariance;
      m_cache.lastUpdateTime = TimeCurrent();
      m_cache.isMeanReverting = true;
      m_cache.isValid = true;
      m_cache.invalidReason = isReasonable ? "" : "Half-life out of range";
      
      Logger.Debug("HalfLife: " + DoubleToString(halfLife, 1) + " bars" +
                  ", Lambda: " + DoubleToString(lambda, 6) +
                  ", O-U Variance: " + DoubleToString(ouVariance, 6));
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Get half-life value                                               |
   //+------------------------------------------------------------------+
   double GetHalfLife()
   {
      return m_cache.halfLife;
   }
   
   //+------------------------------------------------------------------+
   //| Get maximum holding time in bars                                  |
   //+------------------------------------------------------------------+
   int GetMaxHoldingBars()
   {
      if(!m_cache.isValid || !m_cache.isMeanReverting)
         return 100;  // Default fallback
         
      return (int)(m_cache.halfLife * m_exitMultiplier);
   }
   
   //+------------------------------------------------------------------+
   //| Get stop loss z-score distance                                    |
   //+------------------------------------------------------------------+
   double GetStopLossSigma()
   {
      return m_stopLossSigma;
   }
   
   //+------------------------------------------------------------------+
   //| Get O-U variance (for stop-loss calculation)                      |
   //+------------------------------------------------------------------+
   double GetOUVariance()
   {
      return m_cache.ouVariance;
   }
   
   //+------------------------------------------------------------------+
   //| Check if spread is mean-reverting                                 |
   //+------------------------------------------------------------------+
   bool IsMeanReverting()
   {
      return m_cache.isValid && m_cache.isMeanReverting;
   }
   
   //+------------------------------------------------------------------+
   //| Check if half-life is within reasonable range                     |
   //+------------------------------------------------------------------+
   bool IsHalfLifeValid()
   {
      if(!m_cache.isValid || !m_cache.isMeanReverting)
         return false;
         
      return (m_cache.halfLife >= m_minHalfLife && 
              m_cache.halfLife <= m_maxHalfLife);
   }
   
   //+------------------------------------------------------------------+
   //| Get cached half-life data                                         |
   //+------------------------------------------------------------------+
   void GetData(HalfLifeData &data)
   {
      data = m_cache;
   }
   
   //+------------------------------------------------------------------+
   //| Is cache valid                                                    |
   //+------------------------------------------------------------------+
   bool IsValid()
   {
      return m_cache.isValid;
   }
   
   //+------------------------------------------------------------------+
   //| Get lambda coefficient                                            |
   //+------------------------------------------------------------------+
   double GetLambda()
   {
      return m_cache.lambda;
   }
   
   //+------------------------------------------------------------------+
   //| Force recalculation on next update                                |
   //+------------------------------------------------------------------+
   void Invalidate()
   {
      m_barsSinceUpdate = 999;
   }
   
   //+------------------------------------------------------------------+
   //| Check if exit triggered by time                                   |
   //| barsOpen: number of bars since basket opened                      |
   //+------------------------------------------------------------------+
   bool IsTimeExitTriggered(int barsOpen)
   {
      if(!m_cache.isValid || !m_cache.isMeanReverting)
         return (barsOpen > 100);  // Fallback
         
      int maxBars = GetMaxHoldingBars();
      return (barsOpen > maxBars);
   }
   
   //+------------------------------------------------------------------+
   //| Check if stop-loss triggered                                      |
   //| entryZScore: z-score at entry                                     |
   //| currentZScore: current z-score                                    |
   //+------------------------------------------------------------------+
   bool IsStopLossTriggered(double entryZScore, double currentZScore)
   {
      // Stop loss if spread diverges further by stopLossSigma
      double stopDistance = m_stopLossSigma;
      
      if(entryZScore > 0)  // Short basket entry
      {
         // Z-score was positive, should decrease
         // Stop if it increases beyond entry + sigma
         return (currentZScore > entryZScore + stopDistance);
      }
      else  // Long basket entry
      {
         // Z-score was negative, should increase toward 0
         // Stop if it decreases beyond entry - sigma
         return (currentZScore < entryZScore - stopDistance);
      }
   }
};

#endif // DBASKET_HALFLIFEENGINE_MQH
//+------------------------------------------------------------------+
