//+------------------------------------------------------------------+
//|                                  DBasket_CointegrationEngine.mqh |
//|                                D-Basket Correlation Hedging EA   |
//|                                ADF Test for Cointegration        |
//+------------------------------------------------------------------+
#property copyright "D-Basket EA"
#property version   "2.00"
#property strict

#ifndef DBASKET_COINTEGRATIONENGINE_MQH
#define DBASKET_COINTEGRATIONENGINE_MQH

#include "DBasket_Defines.mqh"
#include "DBasket_Structures.mqh"
#include "DBasket_Logger.mqh"

//+------------------------------------------------------------------+
//| Cointegration Data Structure                                      |
//+------------------------------------------------------------------+
struct CointegrationData
{
   double            adfStatistic;        // ADF test statistic
   double            pValue;              // Approximate p-value
   double            beta;                // Hedge ratio from OLS regression
   double            alpha;               // Intercept from OLS regression
   double            residualStdDev;      // Standard deviation of residuals
   datetime          lastUpdateTime;      // Timestamp of last calculation
   bool              isCointegrated;      // True if p-value < threshold
   bool              isValid;             // True if calculation succeeded
   string            invalidReason;       // Description if invalid
   
   void Reset()
   {
      adfStatistic = 0;
      pValue = 1.0;
      beta = 1.0;
      alpha = 0;
      residualStdDev = 0;
      lastUpdateTime = 0;
      isCointegrated = false;
      isValid = false;
      invalidReason = "";
   }
};

//+------------------------------------------------------------------+
//| Cointegration Engine Class                                        |
//| Implements Engle-Granger two-step cointegration test              |
//+------------------------------------------------------------------+
class CCointegrationEngine
{
private:
   // Configuration
   int               m_lookbackPeriod;     // Bars for regression
   int               m_adfLags;            // Lags for ADF test
   double            m_pValueThreshold;    // Cointegration threshold
   int               m_updateIntervalBars; // Bars between updates
   
   // State
   CointegrationData m_cache;
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
   //| OLS Regression: Y = alpha + beta * X + residuals                  |
   //| Returns residuals array                                           |
   //+------------------------------------------------------------------+
   bool OLSRegression(const double &X[], const double &Y[], int count,
                      double &beta, double &alpha, double &residuals[])
   {
      if(count < 30)
      {
         Logger.Warning("OLS: Insufficient data points: " + IntegerToString(count));
         return false;
      }
      
      // Calculate means
      double meanX = ArrayMean(X, count);
      double meanY = ArrayMean(Y, count);
      
      // Calculate covariance and variance
      double covXY = 0;
      double varX = 0;
      
      for(int i = 0; i < count; i++)
      {
         double dx = X[i] - meanX;
         double dy = Y[i] - meanY;
         covXY += dx * dy;
         varX += dx * dx;
      }
      
      // Avoid division by zero
      if(MathAbs(varX) < 0.0000001)
      {
         Logger.Warning("OLS: Near-zero variance in X series");
         return false;
      }
      
      // Calculate coefficients
      beta = covXY / varX;
      alpha = meanY - beta * meanX;
      
      // Calculate residuals
      if(ArrayResize(residuals, count) != count)
         return false;
         
      for(int i = 0; i < count; i++)
      {
         residuals[i] = Y[i] - (alpha + beta * X[i]);
      }
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Augmented Dickey-Fuller Test (simplified, 1 lag)                  |
   //| Tests if series has unit root (non-stationary)                    |
   //| Returns: ADF statistic (more negative = more stationary)          |
   //+------------------------------------------------------------------+
   bool ADFTest(const double &series[], int count, double &adfStat, double &pValue)
   {
      if(count < 50)
      {
         Logger.Warning("ADF: Insufficient data points: " + IntegerToString(count));
         return false;
      }
      
      int n = count - 1;  // Number of differences
      
      // Construct lagged series and first differences
      double y_lag[];
      double delta_y[];
      
      if(ArrayResize(y_lag, n) != n || ArrayResize(delta_y, n) != n)
         return false;
      
      for(int i = 0; i < n; i++)
      {
         y_lag[i] = series[i];
         delta_y[i] = series[i + 1] - series[i];
      }
      
      // Run regression: delta_y = alpha + gamma * y_lag + epsilon
      // We need gamma coefficient and its standard error
      
      // Calculate means
      double meanYLag = ArrayMean(y_lag, n);
      double meanDeltaY = ArrayMean(delta_y, n);
      
      // Calculate covariance and variance for regression
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
         Logger.Warning("ADF: Near-zero variance in lagged series");
         return false;
      }
      
      // Gamma coefficient
      double gamma = covYD / varYLag;
      double alpha = meanDeltaY - gamma * meanYLag;
      
      // Calculate residuals and MSE
      double residualSumSq = 0;
      for(int i = 0; i < n; i++)
      {
         double fitted = alpha + gamma * y_lag[i];
         double resid = delta_y[i] - fitted;
         residualSumSq += resid * resid;
      }
      
      double mse = residualSumSq / (n - 2);  // 2 parameters estimated
      
      // Standard error of gamma
      double seGamma = MathSqrt(mse / varYLag);
      
      if(seGamma < 0.0000001)
      {
         Logger.Warning("ADF: Near-zero standard error");
         return false;
      }
      
      // ADF statistic (t-statistic of gamma)
      adfStat = gamma / seGamma;
      
      // Convert to approximate p-value using MacKinnon critical values
      // Critical values for ADF test with constant, no trend
      // 1%: -3.43, 5%: -2.86, 10%: -2.57
      if(adfStat < -3.43)
         pValue = 0.01;
      else if(adfStat < -2.86)
         pValue = 0.05;
      else if(adfStat < -2.57)
         pValue = 0.10;
      else
         pValue = 0.20;  // Not stationary
      
      return true;
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CCointegrationEngine()
   {
      m_lookbackPeriod = 250;
      m_adfLags = 1;
      m_pValueThreshold = 0.05;
      m_updateIntervalBars = 50;
      m_barsSinceUpdate = 999;  // Force initial calculation
      m_isInitialized = false;
      m_cache.Reset();
   }
   
   //+------------------------------------------------------------------+
   //| Initialize engine                                                 |
   //+------------------------------------------------------------------+
   bool Initialize(int lookbackPeriod, double pValueThreshold, int updateIntervalBars, int adfLags = 1)
   {
      if(lookbackPeriod < 60)
      {
         Logger.Error("Cointegration: Lookback period too short (min 60)");
         return false;
      }
      
      m_lookbackPeriod = lookbackPeriod;
      m_pValueThreshold = pValueThreshold;
      m_updateIntervalBars = updateIntervalBars;
      m_adfLags = adfLags;
      m_barsSinceUpdate = 999;
      m_isInitialized = true;
      m_cache.Reset();
      
      Logger.Info("Cointegration Engine initialized - Lookback: " + IntegerToString(m_lookbackPeriod) +
                 ", P-Value Threshold: " + DoubleToString(m_pValueThreshold, 2) +
                 ", Update Interval: " + IntegerToString(m_updateIntervalBars) + " bars");
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Update cointegration test                                         |
   //| X = synthetic ratio (AUDCAD/NZDCAD)                               |
   //| Y = AUDNZD                                                        |
   //+------------------------------------------------------------------+
   bool Update(const double &syntheticRatio[], const double &audnzd[], int dataCount, bool forceUpdate = false)
   {
      if(!m_isInitialized)
      {
         Logger.Error("Cointegration Engine not initialized");
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
      if(count < 60)
      {
         m_cache.isValid = false;
         m_cache.invalidReason = "Insufficient data: " + IntegerToString(count);
         return false;
      }
      
      // Reset update counter
      m_barsSinceUpdate = 0;
      
      // Step 1: OLS Regression to get residuals
      double residuals[];
      double beta, alpha;
      
      if(!OLSRegression(syntheticRatio, audnzd, count, beta, alpha, residuals))
      {
         m_cache.isValid = false;
         m_cache.invalidReason = "OLS regression failed";
         return false;
      }
      
      // Step 2: ADF Test on residuals
      double adfStat, pValue;
      int residCount = ArraySize(residuals);
      
      if(!ADFTest(residuals, residCount, adfStat, pValue))
      {
         m_cache.isValid = false;
         m_cache.invalidReason = "ADF test failed";
         return false;
      }
      
      // Step 3: Calculate residual statistics
      double residMean = ArrayMean(residuals, residCount);
      double residStdDev = ArrayStdDev(residuals, residCount, residMean);
      
      // Step 4: Update cache
      m_cache.adfStatistic = adfStat;
      m_cache.pValue = pValue;
      m_cache.beta = beta;
      m_cache.alpha = alpha;
      m_cache.residualStdDev = residStdDev;
      m_cache.lastUpdateTime = TimeCurrent();
      m_cache.isCointegrated = (pValue < m_pValueThreshold);
      m_cache.isValid = true;
      m_cache.invalidReason = "";
      
      // Log results
      string status = m_cache.isCointegrated ? "COINTEGRATED" : "NOT COINTEGRATED";
      Logger.Debug("Cointegration Test: " + status + 
                  " - ADF: " + DoubleToString(adfStat, 3) +
                  ", P-Value: " + DoubleToString(pValue, 2) +
                  ", Beta: " + DoubleToString(beta, 4));
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Check if spread is cointegrated                                   |
   //+------------------------------------------------------------------+
   bool IsCointegrated()
   {
      return m_cache.isValid && m_cache.isCointegrated;
   }
   
   //+------------------------------------------------------------------+
   //| Get cached cointegration data                                     |
   //+------------------------------------------------------------------+
   void GetData(CointegrationData &data)
   {
      data = m_cache;
   }
   
   //+------------------------------------------------------------------+
   //| Get ADF statistic                                                 |
   //+------------------------------------------------------------------+
   double GetADFStatistic()
   {
      return m_cache.adfStatistic;
   }
   
   //+------------------------------------------------------------------+
   //| Get p-value                                                       |
   //+------------------------------------------------------------------+
   double GetPValue()
   {
      return m_cache.pValue;
   }
   
   //+------------------------------------------------------------------+
   //| Get hedge ratio (beta)                                            |
   //+------------------------------------------------------------------+
   double GetBeta()
   {
      return m_cache.beta;
   }
   
   //+------------------------------------------------------------------+
   //| Is cache valid                                                    |
   //+------------------------------------------------------------------+
   bool IsValid()
   {
      return m_cache.isValid;
   }
   
   //+------------------------------------------------------------------+
   //| Get reason if invalid                                             |
   //+------------------------------------------------------------------+
   string GetInvalidReason()
   {
      return m_cache.invalidReason;
   }
   
   //+------------------------------------------------------------------+
   //| Force recalculation on next update                                |
   //+------------------------------------------------------------------+
   void Invalidate()
   {
      m_barsSinceUpdate = 999;
   }
};

#endif // DBASKET_COINTEGRATIONENGINE_MQH
//+------------------------------------------------------------------+
