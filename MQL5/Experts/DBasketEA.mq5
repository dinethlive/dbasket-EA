//+------------------------------------------------------------------+
//|                                                   DBasketEA.mq5  |
//|                                   D-Basket Correlation Hedging EA |
//|               Three-Pair Correlation Strategy for AUDCAD/NZDCAD/AUDNZD |
//+------------------------------------------------------------------+
#property copyright "D-Basket EA"
#property version   "1.00"
#property description "Three-pair correlation hedging EA exploiting temporary divergences between AUDCAD, NZDCAD, and AUDNZD"
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

// --- Trading Hours ---
input group "Trading Hours"
input int      InpTradingStartHour = 0;     // Trading start hour (broker time)
input int      InpTradingStartMin = 0;      // Trading start minute
input int      InpTradingEndHour = 23;      // Trading end hour (broker time)
input int      InpTradingEndMin = 59;       // Trading end minute
input bool     InpAvoidRollover = true;     // Avoid rollover period

// --- Technical Settings ---
input group "Technical Settings"
input int      InpMagicNumber = 100000;     // Magic number
input int      InpSlippagePoints = 10;      // Maximum slippage (points)
input ENUM_LOG_LEVEL InpLogLevel = LOG_LEVEL_INFO; // Log level
input bool     InpLogToFile = false;        // Log to file

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
// Configuration
EAConfig g_config;

// Module instances
CCorrelationEngine g_correlationEngine;
CSignalEngine      g_signalEngine;
CTradeWrapper      g_tradeWrapper;
CPositionManager   g_positionManager;
CRiskManager       g_riskManager;

// State
bool g_isInitialized = false;
bool g_tradingEnabled = true;
datetime g_lastTickProcessed = 0;
int g_tickCount = 0;

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
   
   // Risk parameters
   if(InpRiskPercent < 0.1 || InpRiskPercent > 10.0)
   {
      Logger.Error("Invalid risk percent. Must be 0.1-10.0");
      return false;
   }
   
   if(InpMaxDrawdownPct < 5.0 || InpMaxDrawdownPct > 50.0)
   {
      Logger.Error("Invalid max drawdown. Must be 5-50%");
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
      Logger.Error("This EA requires a hedging account to open opposite positions.");
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
   
   // Check connection
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      Logger.Warning("Terminal is not connected to server");
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
      
      // Try to select symbol
      if(!SymbolSelect(symbol, true))
      {
         Logger.Error("Symbol not available: " + symbol);
         return false;
      }
      
      // Check trade mode
      ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
      if(tradeMode != SYMBOL_TRADE_MODE_FULL)
      {
         Logger.Error("Trading not fully allowed on " + symbol + ": " + EnumToString(tradeMode));
         return false;
      }
      
      // Log symbol info
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
      
      Logger.Info("Symbol " + symbol + " - MinLot: " + DoubleToString(minLot, 2) +
                 ", Step: " + DoubleToString(lotStep, 2) +
                 ", Spread: " + DoubleToString(spread * 10000, 1) + " pips");
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
   
   // Log startup
   Logger.LogInitSummary(EA_NAME, EA_VERSION, 
                        AccountInfoDouble(ACCOUNT_BALANCE),
                        (int)AccountInfoInteger(ACCOUNT_LEVERAGE),
                        AccountInfoString(ACCOUNT_SERVER));
   
   // Build configuration from inputs
   BuildConfiguration();
   
   // Validate inputs
   if(!ValidateInputs())
   {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Validate environment
   if(!ValidateEnvironment())
   {
      return INIT_FAILED;
   }
   
   // Validate symbols
   if(!ValidateSymbols())
   {
      return INIT_FAILED;
   }
   
   // Initialize modules
   Logger.Info("Initializing EA modules...");
   
   // Trade wrapper
   if(!g_tradeWrapper.Initialize(g_config.magicNumber, g_config.slippagePoints))
   {
      Logger.Error("Failed to initialize Trade Wrapper");
      return INIT_FAILED;
   }
   
   // Correlation engine
   if(!g_correlationEngine.Initialize(g_config.symbols, g_config.lookbackPeriod, 
                                      g_config.timeframe, g_config.updateIntervalSeconds))
   {
      Logger.Error("Failed to initialize Correlation Engine");
      return INIT_FAILED;
   }
   
   // Signal engine
   if(!g_signalEngine.Initialize(g_config))
   {
      Logger.Error("Failed to initialize Signal Engine");
      return INIT_FAILED;
   }
   
   // Position manager
   if(!g_positionManager.Initialize(g_config, &g_tradeWrapper))
   {
      Logger.Error("Failed to initialize Position Manager");
      return INIT_FAILED;
   }
   
   // Set TP/SL
   g_positionManager.SetTPSL(InpTakeProfitAmount, InpStopLossAmount);
   
   // Risk manager
   if(!g_riskManager.Initialize(g_config))
   {
      Logger.Error("Failed to initialize Risk Manager");
      return INIT_FAILED;
   }
   
   // Recover any existing positions from previous session
   g_positionManager.RecoverFromOpenPositions();
   
   g_isInitialized = true;
   g_tradingEnabled = true;
   
   Logger.Info("EA initialization complete. Ready for trading.");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   string reasonStr;
   switch(reason)
   {
      case REASON_PROGRAM:      reasonStr = "Program"; break;
      case REASON_REMOVE:       reasonStr = "Remove"; break;
      case REASON_RECOMPILE:    reasonStr = "Recompile"; break;
      case REASON_CHARTCHANGE:  reasonStr = "Chart changed"; break;
      case REASON_CHARTCLOSE:   reasonStr = "Chart closed"; break;
      case REASON_PARAMETERS:   reasonStr = "Parameters changed"; break;
      case REASON_ACCOUNT:      reasonStr = "Account changed"; break;
      case REASON_TEMPLATE:     reasonStr = "Template applied"; break;
      case REASON_INITFAILED:   reasonStr = "Init failed"; break;
      case REASON_CLOSE:        reasonStr = "Terminal closed"; break;
      default:                  reasonStr = "Unknown (" + IntegerToString(reason) + ")";
   }
   
   Logger.Info("EA shutdown - Reason: " + reasonStr);
   
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
   
   // Clear chart
   Comment("");
   
   // Deinitialize logger
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
   
   // === Phase 1: Risk Management Check ===
   string riskReason;
   if(!g_riskManager.CheckRiskLimits(riskReason))
   {
      // Check for emergency exit
      string emergencyReason;
      if(g_riskManager.CheckEmergencyExit(emergencyReason))
      {
         Logger.Error("EMERGENCY EXIT: " + emergencyReason);
         if(g_positionManager.HasOpenBasket())
         {
            g_positionManager.CloseBasket(EXIT_EMERGENCY);
         }
      }
      
      g_tradingEnabled = false;
      
      // Update display
      if(g_tickCount % 100 == 0)
         g_riskManager.DisplayMetricsOnChart();
      
      return;
   }
   
   g_tradingEnabled = true;
   
   // === Phase 2: Update Price Buffers ===
   g_correlationEngine.UpdatePriceBuffers();
   
   // === Phase 3: Update Correlation Cache ===
   if(!g_correlationEngine.UpdateCorrelationCache())
   {
      // Not ready or data invalid - skip this tick
      return;
   }
   
   // Get correlation data
   CorrelationData corrData;
   g_correlationEngine.GetCorrelationData(corrData);
   
   // === Phase 4: Position Management ===
   if(g_positionManager.HasOpenBasket())
   {
      // Update basket state
      g_positionManager.UpdateBasketState();
      
      // Check exit signals
      BasketState basket;
      g_positionManager.GetBasketState(basket);
      
      ENUM_EXIT_REASON exitReason;
      if(g_signalEngine.CheckExitSignal(corrData, basket,
                                        g_positionManager.GetTakeProfitAmount(),
                                        g_positionManager.GetStopLossAmount(),
                                        g_positionManager.GetMaxHoldingHours(),
                                        exitReason))
      {
         // Close basket
         double pl = g_positionManager.GetBasketPL();
         g_positionManager.CloseBasket(exitReason);
         
         // Record result
         g_riskManager.RecordBasketClose(pl, pl >= 0);
      }
   }
   else
   {
      // === Phase 5: Signal Generation ===
      string signalFailReason;
      ENUM_BASKET_SIGNAL signal = g_signalEngine.CheckEntrySignal(corrData, false, signalFailReason);
      
      if(signal != SIGNAL_NONE)
      {
         g_riskManager.RecordSignal(true);
         
         // Attempt to open basket
         if(g_positionManager.OpenBasket(signal, corrData.spreadZScore, corrData.corrAUDCAD_NZDCAD))
         {
            g_riskManager.RecordBasketOpen();
         }
      }
      else if(signalFailReason != "")
      {
         // Signal was blocked by filter
         g_riskManager.RecordSignal(false);
         
         // Log filter reason periodically (every 1000 ticks)
         if(g_tickCount % 1000 == 0)
         {
            Logger.Debug("Signal blocked: " + signalFailReason);
         }
      }
   }
   
   // === Phase 6: Display Update ===
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
   // Get statistics
   double profit = TesterStatistics(STAT_PROFIT);
   double maxDD = TesterStatistics(STAT_EQUITY_DD);
   double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);
   int totalTrades = (int)TesterStatistics(STAT_TRADES);
   int winTrades = (int)TesterStatistics(STAT_PROFIT_TRADES);
   
   // Calculate win rate
   double winRate = totalTrades > 0 ? (double)winTrades / totalTrades : 0;
   
   // Custom optimization criterion
   // Prioritize: profit/drawdown ratio, win rate > 65%, profit factor > 1.3
   if(winRate < 0.65 || profitFactor < 1.3 || totalTrades < 20)
      return 0; // Reject parameters that don't meet minimum criteria
   
   // Risk-adjusted return
   double riskAdjustedReturn = maxDD > 0 ? profit / maxDD : 0;
   
   // Combine metrics
   double score = riskAdjustedReturn * profitFactor * winRate;
   
   return score;
}

//+------------------------------------------------------------------+
//| Trade event handler                                               |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Handle trade events if needed
   // (Position state is already updated in OnTick via UpdateBasketState)
}

//+------------------------------------------------------------------+
//| Timer function (if using timer)                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Can be used for periodic tasks independent of ticks
}
//+------------------------------------------------------------------+
