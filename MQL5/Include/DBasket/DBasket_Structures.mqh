//+------------------------------------------------------------------+
//|                                           DBasket_Structures.mqh |
//|                                   D-Basket Correlation Hedging EA |
//|                                   Core Data Structures            |
//+------------------------------------------------------------------+
#property copyright "D-Basket EA"
#property version   "1.00"
#property strict

#ifndef DBASKET_STRUCTURES_MQH
#define DBASKET_STRUCTURES_MQH

#include "DBasket_Defines.mqh"

//+------------------------------------------------------------------+
//| Correlation Data Structure                                        |
//| Encapsulates all correlation engine outputs                       |
//+------------------------------------------------------------------+
struct CorrelationData
{
   // Primary correlation coefficients
   double            corrAUDCAD_NZDCAD;      // Main correlation: AUDCAD vs NZDCAD
   double            corrAUDCAD_AUDNZD;      // Validation: AUDCAD vs AUDNZD
   double            corrNZDCAD_AUDNZD;      // Validation: NZDCAD vs AUDNZD
   
   // Spread and divergence metrics
   double            syntheticRatio;         // AUDCAD / NZDCAD
   double            actualAUDNZD;           // Current AUDNZD close price
   double            spreadValue;            // syntheticRatio - actualAUDNZD
   double            spreadZScore;           // Z-score of current spread
   
   // Statistical parameters
   double            spreadMean;             // Historical mean of spread
   double            spreadStdDev;           // Historical standard deviation
   
   // Metadata
   datetime          calculationTime;        // Timestamp of last calculation
   bool              isValid;                // False if insufficient data or error
   int               lookbackPeriod;         // Number of bars used
   string            invalidReason;          // Description if isValid == false
   
   // Constructor
   void              CorrelationData()
   {
      Reset();
   }
   
   // Reset to default values
   void              Reset()
   {
      corrAUDCAD_NZDCAD = 0;
      corrAUDCAD_AUDNZD = 0;
      corrNZDCAD_AUDNZD = 0;
      syntheticRatio = 0;
      actualAUDNZD = 0;
      spreadValue = 0;
      spreadZScore = 0;
      spreadMean = 0;
      spreadStdDev = 0;
      calculationTime = 0;
      isValid = false;
      lookbackPeriod = 0;
      invalidReason = "";
   }
};

//+------------------------------------------------------------------+
//| Position State Structure                                          |
//| Track individual position within a basket                         |
//+------------------------------------------------------------------+
struct PositionState
{
   // Position identification
   ulong             ticket;                 // MT5 position ticket
   string            symbol;                 // Symbol name
   int               symbolIndex;            // 0=AUDCAD, 1=NZDCAD, 2=AUDNZD
   
   // Position parameters
   ENUM_POSITION_TYPE type;                  // POSITION_TYPE_BUY or SELL
   double            lots;                   // Position volume
   double            openPrice;              // Entry price
   datetime          openTime;               // Position open timestamp
   
   // Risk management
   double            stopLoss;               // SL price (0 if none)
   double            takeProfit;             // TP price (0 if none)
   
   // P&L tracking
   double            currentPrice;           // Last known price
   double            unrealizedPL;           // Floating profit/loss
   double            swap;                   // Accumulated swap
   double            commission;             // Commission paid
   
   // State flags
   bool              isOpen;                 // True if position exists
   string            comment;                // Position comment
   
   // Constructor
   void              PositionState()
   {
      Reset();
   }
   
   // Reset to default values
   void              Reset()
   {
      ticket = 0;
      symbol = "";
      symbolIndex = -1;
      type = POSITION_TYPE_BUY;
      lots = 0;
      openPrice = 0;
      openTime = 0;
      stopLoss = 0;
      takeProfit = 0;
      currentPrice = 0;
      unrealizedPL = 0;
      swap = 0;
      commission = 0;
      isOpen = false;
      comment = "";
   }
};

//+------------------------------------------------------------------+
//| Basket State Structure                                            |
//| Tracks a complete 3-leg basket                                    |
//+------------------------------------------------------------------+
struct BasketState
{
   // Basket identification
   int               basketID;               // Unique basket identifier
   ENUM_BASKET_STATE state;                  // Current basket state
   ENUM_BASKET_SIGNAL direction;             // LONG or SHORT basket
   
   // Timing
   datetime          openTime;               // Basket creation timestamp
   datetime          lastUpdateTime;         // Last state update
   int               barsHeld;               // Number of bars position held
   
   // Position tracking for each leg
   PositionState     positions[NUM_SYMBOLS]; // All three legs
   
   // Entry conditions snapshot
   double            entryZScore;            // Z-score at entry
   double            entryCorrelation;       // Primary correlation at entry
   double            entrySpread;            // Spread value at entry
   
   // P&L tracking
   double            unrealizedPL;           // Total floating P&L
   double            realizedPL;             // Realized P&L (if partially closed)
   
   // Exit tracking
   ENUM_EXIT_REASON  exitReason;             // Reason for exit (when closed)
   
   // Constructor
   void              BasketState()
   {
      Reset();
   }
   
   // Reset to default values
   void              Reset()
   {
      basketID = 0;
      state = BASKET_NONE;
      direction = SIGNAL_NONE;
      openTime = 0;
      lastUpdateTime = 0;
      barsHeld = 0;
      entryZScore = 0;
      entryCorrelation = 0;
      entrySpread = 0;
      unrealizedPL = 0;
      realizedPL = 0;
      exitReason = EXIT_MANUAL;
      
      for(int i = 0; i < NUM_SYMBOLS; i++)
         positions[i].Reset();
   }
   
   // Check if basket is active (has open positions)
   bool              IsActive() const
   {
      return (state == BASKET_OPEN || state == BASKET_PARTIAL);
   }
   
   // Get total lots across all legs
   double            GetTotalLots() const
   {
      double total = 0;
      for(int i = 0; i < NUM_SYMBOLS; i++)
         if(positions[i].isOpen)
            total += positions[i].lots;
      return total;
   }
   
   // Count open legs
   int               CountOpenLegs() const
   {
      int count = 0;
      for(int i = 0; i < NUM_SYMBOLS; i++)
         if(positions[i].isOpen)
            count++;
      return count;
   }
};

//+------------------------------------------------------------------+
//| Performance Metrics Structure                                     |
//| Track EA performance in real-time                                 |
//+------------------------------------------------------------------+
struct PerformanceMetrics
{
   // Account metrics
   double            startingBalance;        // Initial balance at EA start
   double            currentBalance;         // Current balance
   double            currentEquity;          // Current equity
   double            peakEquity;             // Highest equity reached
   
   // P&L tracking
   double            realizedPL;             // Total closed P&L
   double            unrealizedPL;           // Total floating P&L
   double            netPL;                  // realizedPL + unrealizedPL
   
   // Trade statistics
   int               totalBaskets;           // Total baskets opened
   int               closedBaskets;          // Total baskets closed
   int               winningBaskets;         // Profitable closes
   int               losingBaskets;          // Loss closes
   double            winRate;                // winningBaskets / closedBaskets
   double            avgWin;                 // Average winning basket P&L
   double            avgLoss;                // Average losing basket P&L
   double            profitFactor;           // Sum(wins) / abs(Sum(losses))
   
   // Risk metrics
   double            currentDrawdownPercent; // Current drawdown from peak
   double            maxDrawdownPercent;     // Maximum drawdown
   double            maxDrawdownValue;       // Max drawdown in currency
   
   // Daily tracking
   double            dailyPnL;               // Today's P&L
   double            dailyStartEquity;       // Equity at day start
   datetime          dailyResetTime;         // Last daily reset timestamp
   int               consecutiveLosses;      // Current losing streak
   int               maxConsecutiveLosses;   // Worst losing streak
   
   // Operational metrics
   int               totalSignals;           // Signals generated
   int               executedSignals;        // Signals that became trades
   int               filteredSignals;        // Signals blocked by filters
   int               erroredTrades;          // Trade execution errors
   datetime          lastTradeTime;          // Last basket open/close
   
   // Timing
   datetime          metricsStartTime;       // When tracking started
   int               uptimeSeconds;          // Seconds since start
   
   // Constructor
   void              PerformanceMetrics()
   {
      Reset();
   }
   
   // Reset to default values
   void              Reset()
   {
      startingBalance = 0;
      currentBalance = 0;
      currentEquity = 0;
      peakEquity = 0;
      realizedPL = 0;
      unrealizedPL = 0;
      netPL = 0;
      totalBaskets = 0;
      closedBaskets = 0;
      winningBaskets = 0;
      losingBaskets = 0;
      winRate = 0;
      avgWin = 0;
      avgLoss = 0;
      profitFactor = 0;
      currentDrawdownPercent = 0;
      maxDrawdownPercent = 0;
      maxDrawdownValue = 0;
      dailyPnL = 0;
      dailyStartEquity = 0;
      dailyResetTime = 0;
      consecutiveLosses = 0;
      maxConsecutiveLosses = 0;
      totalSignals = 0;
      executedSignals = 0;
      filteredSignals = 0;
      erroredTrades = 0;
      lastTradeTime = 0;
      metricsStartTime = 0;
      uptimeSeconds = 0;
   }
};

//+------------------------------------------------------------------+
//| Trade Log Entry Structure                                         |
//| Record of trade operations for audit                              |
//+------------------------------------------------------------------+
struct TradeLogEntry
{
   // Trade identification
   int               entryID;                // Sequential log entry number
   datetime          timestamp;              // Operation timestamp
   string            operation;              // Operation type description
   
   // Trade details
   int               basketID;               // Basket identifier (-1 if N/A)
   string            symbol;                 // Symbol traded
   ulong             ticket;                 // Position ticket
   ENUM_ORDER_TYPE   orderType;              // Buy/sell
   double            lots;                   // Volume
   double            price;                  // Execution price
   
   // Outcome
   bool              success;                // Operation succeeded
   int               errorCode;              // MT5 error code
   string            errorDescription;       // Error message
   double            pl;                     // P&L (for closes)
   
   // Context
   double            accountBalance;         // Balance at operation
   double            accountEquity;          // Equity at operation
   double            zScore;                 // Z-score at operation
   double            correlation;            // Correlation at operation
   
   // Constructor
   void              TradeLogEntry()
   {
      Reset();
   }
   
   // Reset
   void              Reset()
   {
      entryID = 0;
      timestamp = 0;
      operation = "";
      basketID = -1;
      symbol = "";
      ticket = 0;
      orderType = ORDER_TYPE_BUY;
      lots = 0;
      price = 0;
      success = false;
      errorCode = 0;
      errorDescription = "";
      pl = 0;
      accountBalance = 0;
      accountEquity = 0;
      zScore = 0;
      correlation = 0;
   }
};

//+------------------------------------------------------------------+
//| Price History Buffer Structure                                    |
//| Maintains rolling window for correlation calculations             |
//+------------------------------------------------------------------+
struct PriceHistoryBuffer
{
   double            prices[];               // Price data array
   int               size;                   // Current buffer size
   int               head;                   // Current write position (newest)
   datetime          lastUpdateTime;         // Last update timestamp
   bool              isWarmedUp;             // True when fully populated
   
   // Constructor
   void              PriceHistoryBuffer()
   {
      size = 0;
      head = 0;
      lastUpdateTime = 0;
      isWarmedUp = false;
   }
   
   // Initialize buffer with specific size
   bool              Initialize(int bufferSize)
   {
      if(bufferSize <= 0 || bufferSize > MAX_LOOKBACK_PERIOD)
         return false;
         
      if(ArrayResize(prices, bufferSize) != bufferSize)
         return false;
         
      ArrayInitialize(prices, 0);
      size = bufferSize;
      head = 0;
      lastUpdateTime = 0;
      isWarmedUp = false;
      return true;
   }
   
   // Add new price (circular buffer pattern)
   void              AddPrice(double price, datetime time)
   {
      if(size <= 0)
         return;
         
      head = (head + 1) % size;
      prices[head] = price;
      lastUpdateTime = time;
      
      // Check if warmed up (simple check - all positions written at least once)
      if(!isWarmedUp && head == size - 1)
         isWarmedUp = true;
   }
   
   // Get price at offset from newest (0 = newest, 1 = second newest, etc.)
   double            GetPrice(int offset) const
   {
      if(offset < 0 || offset >= size)
         return 0;
         
      int realIndex = (head - offset + size) % size;
      return prices[realIndex];
   }
   
   // Get all prices in chronological order (oldest first)
   bool              GetPricesOrdered(double &output[]) const
   {
      if(ArrayResize(output, size) != size)
         return false;
         
      for(int i = 0; i < size; i++)
      {
         int srcIndex = (head - size + 1 + i + size) % size;
         output[i] = prices[srcIndex];
      }
      return true;
   }
};

//+------------------------------------------------------------------+
//| EA Configuration Structure                                        |
//| Groups all user-configurable settings                             |
//+------------------------------------------------------------------+
struct EAConfig
{
   // Symbol configuration
   string            symbols[NUM_SYMBOLS];   // Full symbol names with suffix
   ENUM_TIMEFRAMES   timeframe;              // Timeframe for calculations
   
   // Correlation engine parameters
   int               lookbackPeriod;         // Rolling window size
   int               updateIntervalSeconds;  // Cache update frequency
   
   // Signal generation parameters
   double            zScoreEntryThreshold;   // Minimum |z-score| for entry
   double            zScoreExitThreshold;    // Maximum |z-score| for exit
   double            minCorrelation;         // Minimum acceptable correlation
   double            maxSpreadPips;          // Maximum spread per symbol
   
   // Risk management parameters
   double            baseLotSize;            // Base lot size per leg
   double            riskPercentPerBasket;   // Risk % per basket
   double            maxDrawdownPercent;     // Circuit breaker threshold
   double            maxDailyLossPercent;    // Daily loss limit %
   double            maxDailyLossAmount;     // Daily loss limit amount
   int               maxOpenBaskets;         // Maximum concurrent baskets
   int               maxHoldingHours;        // Maximum basket hold time
   
   // Trading hours
   int               tradingStartHour;       // Start hour (broker time)
   int               tradingStartMinute;     // Start minute
   int               tradingEndHour;         // End hour (broker time)
   int               tradingEndMinute;       // End minute
   bool              avoidRollover;          // Skip rollover period
   
   // Technical settings
   int               magicNumber;            // EA magic number
   int               slippagePoints;         // Maximum slippage
   int               maxRetries;             // Trade retry limit
   ENUM_LOG_LEVEL    logLevel;               // Logging verbosity
   bool              logToFile;              // Enable file logging
   ENUM_SIZING_MODE  sizingMode;             // Position sizing mode
   
   // Constructor
   void              EAConfig()
   {
      SetDefaults();
   }
   
   // Set default values
   void              SetDefaults()
   {
      symbols[0] = DEFAULT_SYMBOL_AUDCAD;
      symbols[1] = DEFAULT_SYMBOL_NZDCAD;
      symbols[2] = DEFAULT_SYMBOL_AUDNZD;
      timeframe = PERIOD_M15;
      lookbackPeriod = 250;
      updateIntervalSeconds = DEFAULT_CACHE_UPDATE_INTERVAL;
      zScoreEntryThreshold = 2.5;
      zScoreExitThreshold = 0.5;
      minCorrelation = 0.75;
      maxSpreadPips = 3.0;
      baseLotSize = 0.01;
      riskPercentPerBasket = 1.0;
      maxDrawdownPercent = DEFAULT_MAX_DRAWDOWN_PERCENT;
      maxDailyLossPercent = 5.0;
      maxDailyLossAmount = DEFAULT_DAILY_LOSS_LIMIT;
      maxOpenBaskets = 1;
      maxHoldingHours = DEFAULT_MAX_HOLDING_HOURS;
      tradingStartHour = 0;
      tradingStartMinute = 0;
      tradingEndHour = 23;
      tradingEndMinute = 59;
      avoidRollover = true;
      magicNumber = 100000;
      slippagePoints = DEFAULT_SLIPPAGE_POINTS;
      maxRetries = MAX_RETRY_ATTEMPTS;
      logLevel = LOG_LEVEL_INFO;
      logToFile = false;
      sizingMode = SIZING_FIXED;
   }
};

#endif // DBASKET_STRUCTURES_MQH
//+------------------------------------------------------------------+
