//+------------------------------------------------------------------+
//|                                                DBasketEA_v2.mq5  |
//|                                D-Basket Correlation Hedging EA   |
//|                                Version 2.0 - Advanced Optimized  |
//+------------------------------------------------------------------+
#property copyright "D-Basket EA"
#property version   "2.00"
#property description "Three-pair correlation hedging EA v2.0 with Cointegration, Half-Life, and ATR Balancing"
#property strict

//+------------------------------------------------------------------+
//| Include Files                                                     |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include "..\Include\DBasket\DBasket_Defines.mqh"
#include "..\Include\DBasket\DBasket_Structures.mqh"
#include "..\Include\DBasket\DBasket_Logger.mqh"
#include "..\Include\DBasket\DBasket_CorrelationEngine.mqh"
#include "..\Include\DBasket\DBasket_SignalEngine.mqh"
#include "..\Include\DBasket\DBasket_TradeWrapper.mqh"
#include "..\Include\DBasket\DBasket_PositionManager.mqh"
#include "..\Include\DBasket\DBasket_RiskManager.mqh"
// v2.0 Optimization Modules
#include "..\Include\DBasket\DBasket_CointegrationEngine.mqh"
#include "..\Include\DBasket\DBasket_HalfLifeEngine.mqh"
#include "..\Include\DBasket\DBasket_VolatilityBalancer.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
// --- Symbol Configuration ---
input group "Symbol Settings"
input string   InpSymbolSuffix = "";        // Symbol suffix (e.g., ".m", "_sb")

// --- Correlation Engine ---
input group "Correlation Engine"
input int      InpLookbackPeriod = 250;     // Lookback period (bars)
input int      InpCacheUpdateSec = 30;      // Cache update interval (seconds)

// --- Signal Generation ---
input group "Signal Generation"
input double   InpZScoreEntry = 2.5;        // Entry Z-Score threshold
input double   InpZScoreExit = 0.5;         // Exit Z-Score threshold
input double   InpMinCorrelation = 0.75;    // Minimum correlation threshold
input double   InpMaxSpreadPips = 3.0;      // Maximum spread (pips per symbol)

// --- Risk Management ---
input group "Risk Management"
input double   InpFixedLotSize = 0.01;      // Fixed lot size per leg
input double   InpRiskPercent = 1.0;        // Risk % per basket (if dynamic sizing)
input bool     InpUseFixedLots = true;      // Use fixed lot size
input double   InpMaxDrawdownPct = 15.0;    // Max drawdown % before halt
input double   InpDailyLossLimit = 100.0;   // Daily loss limit ($)
input double   InpDailyLossPct = 5.0;       // Daily loss limit (%)
input int      InpMaxHoldingHours = 24;     // Maximum basket holding hours
input double   InpTakeProfitAmount = 10.0;  // Take profit per basket ($)
input double   InpStopLossAmount = 15.0;    // Stop loss per basket ($)

// === v2.0 OPTIMIZATION SETTINGS ===

// --- Cointegration Settings ---
input group "=== Cointegration Filter (v2.0) ==="
input bool     InpCointEnabled = true;      // Enable Cointegration Filter?
input double   InpCointPValue = 0.05;       // P-Value Threshold (0.01-0.10)
input int      InpCointUpdateBars = 50;     // Update Interval (bars)
input int      InpCointADFLags = 1;         // ADF Regression Lags

// --- Half-Life Settings ---
input group "=== Half-Life Exits (v2.0) ==="
input bool     InpHLEnabled = true;         // Enable Half-Life Exits?
input int      InpHLUpdateBars = 20;        // Update Interval (bars)
input int      InpHLMinValue = 10;          // Minimum Half-Life (bars)
input int      InpHLMaxValue = 500;         // Maximum Half-Life (bars)
input double   InpHLExitMultiplier = 2.0;   // Max Hold = Multiplier × HalfLife
input double   InpHLStopLossSigma = 1.5;    // Stop-Loss Distance (sigma)

// --- ATR Position Sizing ---
input group "=== ATR Position Sizing (v2.0) ==="
input bool     InpATREnabled = true;        // Enable ATR Sizing?
input int      InpATRPeriod = 14;           // ATR Period
input double   InpATRMinWeight = 0.15;      // Minimum Weight per Symbol
input double   InpATRMaxWeight = 0.50;      // Maximum Weight per Symbol

// --- Trading Hours ---
input group "Trading Hours"
input int      InpTradingStartHour = 0;     // Trading start hour (broker time)
input int      InpTradingStartMin = 0;      // Trading start minute
input int      InpTradingEndHour = 23;      // Trading end hour (broker time)
input int      InpTradingEndMin = 59;       // Trading end minute
input bool     InpAvoidRollover = true;     // Avoid rollover period

// --- Technical Settings ---
input group "Technical Settings"
input int      InpMagicNumber = 200000;     // Magic number (v2.0)
input int      InpSlippagePoints = 10;      // Maximum slippage (points)
input ENUM_LOG_LEVEL InpLogLevel = LOG_LEVEL_INFO; // Log level
input bool     InpLogToFile = false;        // Log to file

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
// Configuration
EAConfig g_config;

// Core modules
CCorrelationEngine g_correlationEngine;
CSignalEngine      g_signalEngine;
CTradeWrapper      g_tradeWrapper;
CPositionManager   g_positionManager;
CRiskManager       g_riskManager;

// v2.0 Optimization modules
CCointegrationEngine g_cointegrationEngine;
CHalfLifeEngine      g_halfLifeEngine;
CVolatilityBalancer  g_volatilityBalancer;

// State
bool g_isInitialized = false;
bool g_tradingEnabled = true;
datetime g_lastTickProcessed = 0;
int g_tickCount = 0;
int g_barCount = 0;
datetime g_lastBarTime = 0;

// v2.0 basket tracking
double g_entryZScore = 0;
int g_barsOpenCount = 0;

//+------------------------------------------------------------------+
//| Build configuration from inputs                                   |
//+------------------------------------------------------------------+
void BuildConfiguration()
{
   g_config.SetDefaults();
   
   // Symbol configuration
   g_config.symbols[SYMBOL_AUDCAD] = DEFAULT_SYMBOL_AUDCAD + InpSymbolSuffix;
   g_config.symbols[SYMBOL_NZDCAD] = DEFAULT_SYMBOL_NZDCAD + InpSymbolSuffix;
   g_config.symbols[SYMBOL_AUDNZD] = DEFAULT_SYMBOL_AUDNZD + InpSymbolSuffix;
   g_config.timeframe = Period();
   
   // Correlation engine
   g_config.lookbackPeriod = InpLookbackPeriod;
   g_config.updateIntervalSeconds = InpCacheUpdateSec;
   
   // Signal generation
   g_config.zScoreEntryThreshold = InpZScoreEntry;
   g_config.zScoreExitThreshold = InpZScoreExit;
   g_config.minCorrelation = InpMinCorrelation;
   g_config.maxSpreadPips = InpMaxSpreadPips;
   
   // Risk management
   g_config.baseLotSize = InpFixedLotSize;
   g_config.riskPercentPerBasket = InpRiskPercent;
   g_config.sizingMode = InpUseFixedLots ? SIZING_FIXED : SIZING_RISK_BASED;
   g_config.maxDrawdownPercent = InpMaxDrawdownPct;
   g_config.maxDailyLossPercent = InpDailyLossPct;
   g_config.maxDailyLossAmount = InpDailyLossLimit;
   g_config.maxHoldingHours = InpMaxHoldingHours;
   
   // Trading hours
   g_config.tradingStartHour = InpTradingStartHour;
   g_config.tradingStartMinute = InpTradingStartMin;
   g_config.tradingEndHour = InpTradingEndHour;
   g_config.tradingEndMinute = InpTradingEndMin;
   g_config.avoidRollover = InpAvoidRollover;
   
   // Technical
   g_config.magicNumber = InpMagicNumber;
   g_config.slippagePoints = InpSlippagePoints;
   g_config.logLevel = InpLogLevel;
   g_config.logToFile = InpLogToFile;
}

//+------------------------------------------------------------------+
//| Validate input parameters                                         |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
   // Lookback period
   if(InpLookbackPeriod < MIN_LOOKBACK_PERIOD || InpLookbackPeriod > MAX_LOOKBACK_PERIOD)
   {
      Logger.Error("Invalid lookback period. Must be " + IntegerToString(MIN_LOOKBACK_PERIOD) + 
                  "-" + IntegerToString(MAX_LOOKBACK_PERIOD));
      return false;
   }
   
   // Z-score thresholds
   if(InpZScoreEntry <= 0 || InpZScoreEntry > 5.0)
   {
      Logger.Error("Invalid entry Z-score. Must be 0-5.0");
      return false;
   }
   
   if(InpZScoreExit < 0 || InpZScoreExit >= InpZScoreEntry)
   {
      Logger.Error("Invalid exit Z-score. Must be 0 to less than entry threshold");
      return false;
   }
   
   // Correlation
   if(InpMinCorrelation < 0.5 || InpMinCorrelation > 0.95)
   {
      Logger.Error("Invalid minimum correlation. Must be 0.5-0.95");
      return false;
   }
   
   // v2.0 Cointegration validation
   if(InpCointPValue < 0.01 || InpCointPValue > 0.20)
   {
      Logger.Error("Invalid cointegration p-value. Must be 0.01-0.20");
      return false;
   }
   
   // v2.0 Half-life validation
   if(InpHLMinValue < 1 || InpHLMinValue > InpHLMaxValue)
   {
      Logger.Error("Invalid half-life range");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Validate trading environment                                      |
//+------------------------------------------------------------------+
bool ValidateEnvironment()
{
   // Check account type (must be hedging)
   ENUM_ACCOUNT_MARGIN_MODE marginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(marginMode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Logger.Error("FATAL: Hedging account required. Current mode: " + EnumToString(marginMode));
      return false;
   }
   
   // Check if trading allowed
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Logger.Error("Trading is not allowed in terminal settings");
      return false;
   }
   
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      Logger.Error("Automated trading is not allowed for this EA");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Validate symbols                                                  |
//+------------------------------------------------------------------+
bool ValidateSymbols()
{
   for(int i = 0; i < NUM_SYMBOLS; i++)
   {
      string symbol = g_config.symbols[i];
      
      if(!SymbolSelect(symbol, true))
      {
         Logger.Error("Symbol not available: " + symbol);
         return false;
      }
      
      ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
      if(tradeMode != SYMBOL_TRADE_MODE_FULL)
      {
         Logger.Error("Trading not fully allowed on " + symbol);
         return false;
      }
      
      Logger.Info("Symbol validated: " + symbol);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                           |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(g_config.symbols[0], Period(), 0);
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      g_barCount++;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate spread series for statistical tests                     |
//+------------------------------------------------------------------+
bool CalculateSpreadSeries(double &spreadSeries[], double &syntheticRatio[], double &audnzd[], int count)
{
   // Get price data
   double audcadClose[], nzdcadClose[], audnzdClose[];
   
   if(CopyClose(g_config.symbols[SYMBOL_AUDCAD], Period(), 0, count, audcadClose) != count)
      return false;
   if(CopyClose(g_config.symbols[SYMBOL_NZDCAD], Period(), 0, count, nzdcadClose) != count)
      return false;
   if(CopyClose(g_config.symbols[SYMBOL_AUDNZD], Period(), 0, count, audnzdClose) != count)
      return false;
   
   // Resize output arrays
   ArrayResize(spreadSeries, count);
   ArrayResize(syntheticRatio, count);
   ArrayResize(audnzd, count);
   
   // Calculate spread and synthetic ratio
   for(int i = 0; i < count; i++)
   {
      syntheticRatio[i] = (nzdcadClose[i] > 0) ? audcadClose[i] / nzdcadClose[i] : 0;
      audnzd[i] = audnzdClose[i];
      spreadSeries[i] = audnzdClose[i] - syntheticRatio[i];
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize logger first
   Logger.Initialize(InpLogLevel, InpLogToFile);
   
   Logger.Info("=== D-Basket EA v2.0 OPTIMIZED ===");
   Logger.Info("Features: Cointegration + Half-Life + ATR Balancing");
   
   // Build configuration from inputs
   BuildConfiguration();
   
   // Validate inputs
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;
   
   // Validate environment
   if(!ValidateEnvironment())
      return INIT_FAILED;
   
   // Validate symbols
   if(!ValidateSymbols())
      return INIT_FAILED;
   
   // Initialize core modules
   Logger.Info("Initializing core modules...");
   
   if(!g_tradeWrapper.Initialize(g_config.magicNumber, g_config.slippagePoints))
   {
      Logger.Error("Failed to initialize Trade Wrapper");
      return INIT_FAILED;
   }
   
   if(!g_correlationEngine.Initialize(g_config.symbols, g_config.lookbackPeriod, 
                                      g_config.timeframe, g_config.updateIntervalSeconds))
   {
      Logger.Error("Failed to initialize Correlation Engine");
      return INIT_FAILED;
   }
   
   if(!g_signalEngine.Initialize(g_config))
   {
      Logger.Error("Failed to initialize Signal Engine");
      return INIT_FAILED;
   }
   
   if(!g_positionManager.Initialize(g_config, &g_tradeWrapper))
   {
      Logger.Error("Failed to initialize Position Manager");
      return INIT_FAILED;
   }
   
   g_positionManager.SetTPSL(InpTakeProfitAmount, InpStopLossAmount);
   
   if(!g_riskManager.Initialize(g_config))
   {
      Logger.Error("Failed to initialize Risk Manager");
      return INIT_FAILED;
   }
   
   // === Initialize v2.0 Optimization Modules ===
   Logger.Info("Initializing v2.0 optimization modules...");
   
   // Cointegration Engine
   if(InpCointEnabled)
   {
      if(!g_cointegrationEngine.Initialize(InpLookbackPeriod, InpCointPValue, 
                                           InpCointUpdateBars, InpCointADFLags))
      {
         Logger.Error("Failed to initialize Cointegration Engine");
         return INIT_FAILED;
      }
      Logger.Info("Cointegration Filter ENABLED (p < " + DoubleToString(InpCointPValue, 2) + ")");
   }
   else
   {
      Logger.Info("Cointegration Filter DISABLED");
   }
   
   // Half-Life Engine
   if(InpHLEnabled)
   {
      if(!g_halfLifeEngine.Initialize(InpLookbackPeriod, InpHLUpdateBars,
                                      InpHLMinValue, InpHLMaxValue,
                                      InpHLExitMultiplier, InpHLStopLossSigma))
      {
         Logger.Error("Failed to initialize Half-Life Engine");
         return INIT_FAILED;
      }
      Logger.Info("Half-Life Exits ENABLED (max hold = " + DoubleToString(InpHLExitMultiplier, 1) + " × halflife)");
   }
   else
   {
      Logger.Info("Half-Life Exits DISABLED");
   }
   
   // Volatility Balancer
   if(InpATREnabled)
   {
      if(!g_volatilityBalancer.Initialize(g_config.symbols, InpATRPeriod,
                                          InpATRMinWeight, InpATRMaxWeight, true))
      {
         Logger.Error("Failed to initialize Volatility Balancer");
         return INIT_FAILED;
      }
      Logger.Info("ATR Position Sizing ENABLED (period = " + IntegerToString(InpATRPeriod) + ")");
   }
   else
   {
      Logger.Info("ATR Position Sizing DISABLED");
   }
   
   // Recover existing positions
   g_positionManager.RecoverFromOpenPositions();
   
   g_isInitialized = true;
   g_tradingEnabled = true;
   g_lastBarTime = iTime(g_config.symbols[0], Period(), 0);
   
   Logger.Info("EA v2.0 initialization complete. Ready for optimized trading.");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Logger.Info("EA v2.0 shutdown - Reason: " + IntegerToString(reason));
   
   // Log final statistics
   PerformanceMetrics metrics;
   g_riskManager.GetMetrics(metrics);
   
   Logger.Info("Final Statistics:");
   Logger.Info("  Total Baskets: " + IntegerToString(metrics.totalBaskets));
   Logger.Info("  Closed: " + IntegerToString(metrics.closedBaskets) +
              " (Win: " + IntegerToString(metrics.winningBaskets) +
              ", Loss: " + IntegerToString(metrics.losingBaskets) + ")");
   Logger.Info("  Win Rate: " + DoubleToString(metrics.winRate * 100, 1) + "%");
   Logger.Info("  Realized P/L: $" + DoubleToString(metrics.realizedPL, 2));
   Logger.Info("  Max Drawdown: " + DoubleToString(metrics.maxDrawdownPercent, 2) + "%");
   
   Comment("");
   Logger.Deinitialize();
   g_isInitialized = false;
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_isInitialized)
      return;
      
   g_tickCount++;
   bool isNewBar = IsNewBar();
   
   // === Phase 1: Risk Management Check ===
   string riskReason;
   if(!g_riskManager.CheckRiskLimits(riskReason))
   {
      string emergencyReason;
      if(g_riskManager.CheckEmergencyExit(emergencyReason))
      {
         Logger.Error("EMERGENCY EXIT: " + emergencyReason);
         if(g_positionManager.HasOpenBasket())
            g_positionManager.CloseBasket(EXIT_EMERGENCY);
      }
      
      g_tradingEnabled = false;
      if(g_tickCount % 100 == 0)
         g_riskManager.DisplayMetricsOnChart();
      return;
   }
   
   g_tradingEnabled = true;
   
   // === Phase 2: Update Price Buffers ===
   g_correlationEngine.UpdatePriceBuffers();
   
   // === Phase 3: Update Correlation Cache ===
   if(!g_correlationEngine.UpdateCorrelationCache())
      return;
   
   CorrelationData corrData;
   g_correlationEngine.GetCorrelationData(corrData);
   
   // === Phase 4: Update v2.0 Optimization Modules (on new bar) ===
   if(isNewBar)
   {
      // Update basket bar counter if open
      if(g_positionManager.HasOpenBasket())
         g_barsOpenCount++;
      
      // Calculate spread series for statistical tests
      double spreadSeries[], syntheticRatio[], audnzd[];
      int dataCount = InpLookbackPeriod;
      
      if(CalculateSpreadSeries(spreadSeries, syntheticRatio, audnzd, dataCount))
      {
         // Update Cointegration
         if(InpCointEnabled)
         {
            g_cointegrationEngine.Update(syntheticRatio, audnzd, dataCount);
         }
         
         // Update Half-Life
         if(InpHLEnabled)
         {
            g_halfLifeEngine.Update(spreadSeries, dataCount);
         }
      }
      
      // Update ATR weights
      if(InpATREnabled)
      {
         g_volatilityBalancer.Update();
      }
   }
   
   // === Phase 5: Position Management ===
   if(g_positionManager.HasOpenBasket())
   {
      g_positionManager.UpdateBasketState();
      
      BasketState basket;
      g_positionManager.GetBasketState(basket);
      
      ENUM_EXIT_REASON exitReason = EXIT_NONE;
      
      // Check standard exit signals first
      if(g_signalEngine.CheckExitSignal(corrData, basket,
                                        g_positionManager.GetTakeProfitAmount(),
                                        g_positionManager.GetStopLossAmount(),
                                        g_positionManager.GetMaxHoldingHours(),
                                        exitReason))
      {
         // Standard exit triggered
      }
      // v2.0: Check half-life based exits
      else if(InpHLEnabled && g_halfLifeEngine.IsValid())
      {
         // Check time-based exit
         if(g_halfLifeEngine.IsTimeExitTriggered(g_barsOpenCount))
         {
            exitReason = EXIT_MAX_TIME;
            Logger.Info("Half-Life time exit triggered (bars: " + IntegerToString(g_barsOpenCount) + 
                       ", max: " + IntegerToString(g_halfLifeEngine.GetMaxHoldingBars()) + ")");
         }
         // Check variance-based stop loss
         else if(g_halfLifeEngine.IsStopLossTriggered(g_entryZScore, corrData.spreadZScore))
         {
            exitReason = EXIT_STOP_LOSS;
            Logger.Info("Half-Life variance stop triggered (entry z: " + DoubleToString(g_entryZScore, 2) +
                       ", current z: " + DoubleToString(corrData.spreadZScore, 2) + ")");
         }
      }
      // v2.0: Check cointegration breakdown
      else if(InpCointEnabled && g_cointegrationEngine.IsValid())
      {
         if(!g_cointegrationEngine.IsCointegrated())
         {
            // Cointegration broke down - consider exiting
            if(g_cointegrationEngine.GetPValue() > 0.10)
            {
               exitReason = EXIT_CORRELATION_BREAK;
               Logger.Warning("Cointegration breakdown - p-value: " + 
                             DoubleToString(g_cointegrationEngine.GetPValue(), 2));
            }
         }
      }
      
      // Execute exit if triggered
      if(exitReason != EXIT_NONE)
      {
         double pl = g_positionManager.GetBasketPL();
         g_positionManager.CloseBasket(exitReason);
         g_riskManager.RecordBasketClose(pl, pl >= 0);
         g_barsOpenCount = 0;
         g_entryZScore = 0;
      }
   }
   else
   {
      // === Phase 6: Signal Generation with v2.0 Filters ===
      string signalFailReason;
      ENUM_BASKET_SIGNAL signal = SIGNAL_NONE;
      
      // v2.0 Pre-filter: Check cointegration before expensive signal calculation
      bool cointValid = true;
      if(InpCointEnabled)
      {
         if(!g_cointegrationEngine.IsCointegrated())
         {
            cointValid = false;
            signalFailReason = "Not cointegrated (p=" + 
                              DoubleToString(g_cointegrationEngine.GetPValue(), 2) + ")";
         }
      }
      
      // v2.0 Pre-filter: Check half-life validity
      bool hlValid = true;
      if(InpHLEnabled)
      {
         if(!g_halfLifeEngine.IsHalfLifeValid())
         {
            hlValid = false;
            if(signalFailReason == "")
               signalFailReason = "Invalid half-life (" + 
                                 DoubleToString(g_halfLifeEngine.GetHalfLife(), 1) + " bars)";
         }
      }
      
      // Only check entry signal if v2.0 pre-filters pass
      if(cointValid && hlValid)
      {
         signal = g_signalEngine.CheckEntrySignal(corrData, false, signalFailReason);
      }
      
      if(signal != SIGNAL_NONE)
      {
         g_riskManager.RecordSignal(true);
         
         // v2.0: Calculate ATR-weighted lot sizes
         double lots[NUM_SYMBOLS];
         if(InpATREnabled && g_volatilityBalancer.IsValid())
         {
            g_volatilityBalancer.CalculateWeightedLots(InpFixedLotSize, lots);
         }
         else
         {
            for(int i = 0; i < NUM_SYMBOLS; i++)
               lots[i] = InpFixedLotSize;
         }
         
         // Attempt to open basket (using standard method for now)
         if(g_positionManager.OpenBasket(signal, corrData.spreadZScore, corrData.corrAUDCAD_NZDCAD))
         {
            g_riskManager.RecordBasketOpen();
            g_barsOpenCount = 0;
            g_entryZScore = corrData.spreadZScore;
            
            // Log v2.0 entry stats
            if(InpCointEnabled)
               Logger.Info("Entry cointegration p-value: " + DoubleToString(g_cointegrationEngine.GetPValue(), 3));
            if(InpHLEnabled)
               Logger.Info("Entry half-life: " + DoubleToString(g_halfLifeEngine.GetHalfLife(), 1) + 
                          " bars (max hold: " + IntegerToString(g_halfLifeEngine.GetMaxHoldingBars()) + ")");
         }
      }
      else if(signalFailReason != "" && g_tickCount % 1000 == 0)
      {
         g_riskManager.RecordSignal(false);
         Logger.Debug("Signal blocked: " + signalFailReason);
      }
   }
   
   // === Phase 7: Display Update ===
   if(g_tickCount % 50 == 0)
   {
      g_riskManager.DisplayMetricsOnChart();
   }
}

//+------------------------------------------------------------------+
//| Tester function for custom optimization criterion                 |
//+------------------------------------------------------------------+
double OnTester()
{
   double profit = TesterStatistics(STAT_PROFIT);
   double maxDD = TesterStatistics(STAT_EQUITY_DD);
   double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);
   int totalTrades = (int)TesterStatistics(STAT_TRADES);
   int winTrades = (int)TesterStatistics(STAT_PROFIT_TRADES);
   
   double winRate = totalTrades > 0 ? (double)winTrades / totalTrades : 0;
   
   // v2.0: Stricter criteria
   if(winRate < 0.70 || profitFactor < 1.5 || totalTrades < 30)
      return 0;
   
   double riskAdjustedReturn = maxDD > 0 ? profit / maxDD : 0;
   double score = riskAdjustedReturn * profitFactor * winRate;
   
   return score;
}

//+------------------------------------------------------------------+
//| Trade event handler                                               |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Handle trade events if needed
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Can be used for periodic tasks independent of ticks
}
//+------------------------------------------------------------------+
