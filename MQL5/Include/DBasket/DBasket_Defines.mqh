//+------------------------------------------------------------------+
//|                                              DBasket_Defines.mqh |
//|                                   D-Basket Correlation Hedging EA |
//|                             Constants, Enums, and Macros          |
//+------------------------------------------------------------------+
#property copyright "D-Basket EA"
#property version   "1.00"
#property strict

#ifndef DBASKET_DEFINES_MQH
#define DBASKET_DEFINES_MQH

//+------------------------------------------------------------------+
//| Symbol Configuration                                              |
//+------------------------------------------------------------------+
#define SYMBOL_AUDCAD     0
#define SYMBOL_NZDCAD     1
#define SYMBOL_AUDNZD     2
#define NUM_SYMBOLS       3

// Maximum lookback period for correlation calculation
#define MAX_LOOKBACK_PERIOD   1000
#define MIN_LOOKBACK_PERIOD   50

// Cache update interval defaults (seconds)
#define DEFAULT_CACHE_UPDATE_INTERVAL   30

// Risk management defaults
#define DEFAULT_MAX_DRAWDOWN_PERCENT    15.0
#define DEFAULT_DAILY_LOSS_LIMIT        100.0
#define DEFAULT_MIN_MARGIN_LEVEL        200.0
#define DEFAULT_WARNING_MARGIN_LEVEL    500.0

// Circuit breaker defaults
#define CB_WARNING_DRAWDOWN_PERCENT     8.0
#define CB_TRIP_DRAWDOWN_PERCENT        15.0
#define CB_MAX_CONSECUTIVE_LOSSES       6

// Position management
#define MAX_OPEN_BASKETS                5
#define DEFAULT_MAX_HOLDING_HOURS       24

// Execution
#define DEFAULT_SLIPPAGE_POINTS         10
#define MAX_RETRY_ATTEMPTS              3
#define RETRY_DELAY_MS                  500

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+

//--- Basket Signal Types
enum ENUM_BASKET_SIGNAL
{
   SIGNAL_NONE = 0,           // No signal
   SIGNAL_LONG_BASKET,        // Long basket (expect AUDNZD to rise)
   SIGNAL_SHORT_BASKET,       // Short basket (expect AUDNZD to fall)
   SIGNAL_EXIT                // Exit existing basket
};

//--- Basket State
enum ENUM_BASKET_STATE
{
   BASKET_NONE = 0,           // No active basket
   BASKET_ENTRY_PENDING,      // Entry signal detected, awaiting execution
   BASKET_OPEN,               // Basket fully opened
   BASKET_PARTIAL,            // Only some legs opened (error state)
   BASKET_EXIT_PENDING,       // Exit signal detected, closing in progress
   BASKET_CLOSED              // Basket closed, ready for next cycle
};

//--- Circuit Breaker States
enum ENUM_CIRCUIT_BREAKER_STATE
{
   CB_NORMAL = 0,             // Trading allowed
   CB_WARNING,                // Warning issued, reduced operations
   CB_TRIPPED                 // Circuit breaker active, trading halted
};

//--- Logging Levels
enum ENUM_LOG_LEVEL
{
   LOG_LEVEL_NONE = 0,        // No logging
   LOG_LEVEL_ERROR,           // Critical errors only
   LOG_LEVEL_WARNING,         // Errors and warnings
   LOG_LEVEL_INFO,            // Normal operations
   LOG_LEVEL_DEBUG            // Detailed debugging
};

//--- Position Sizing Modes
enum ENUM_SIZING_MODE
{
   SIZING_FIXED = 0,          // Fixed lot size
   SIZING_RISK_BASED          // Risk-based position sizing
};

//--- Exit Reasons
enum ENUM_EXIT_REASON
{
   EXIT_NONE = 0,             // No exit reason
   EXIT_MEAN_REVERSION,       // Z-score returned to exit threshold
   EXIT_TAKE_PROFIT,          // Take profit target reached
   EXIT_STOP_LOSS,            // Stop loss triggered
   EXIT_MAX_TIME,             // Maximum holding time exceeded
   EXIT_CORRELATION_BREAK,    // Correlation dropped below minimum
   EXIT_RISK_LIMIT,           // Risk limit breached
   EXIT_EMERGENCY,            // Emergency exit (margin, massive loss)
   EXIT_MANUAL                // Manual close request
};

//+------------------------------------------------------------------+
//| Helper Macros                                                     |
//+------------------------------------------------------------------+

// Get opposite order type
#define OPPOSITE_ORDER_TYPE(type) ((type) == ORDER_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY)

// Check if value is valid (not NaN or INF)
#define IS_VALID_DOUBLE(x) (!MathIsValidNumber(x) ? false : ((x) != EMPTY_VALUE))

// Safe division to avoid divide by zero
#define SAFE_DIVIDE(num, den) ((den) == 0 ? 0 : (num) / (den))

// Convert pips to points (for 5-digit brokers)
#define PIPS_TO_POINTS(pips, symbol) ((int)((pips) / SymbolInfoDouble(symbol, SYMBOL_POINT) * 10))

// Clamp value within range
#define CLAMP(val, minVal, maxVal) (MathMax((minVal), MathMin((maxVal), (val))))

//+------------------------------------------------------------------+
//| String Constants                                                  |
//+------------------------------------------------------------------+
#define EA_NAME           "D-Basket Correlation Hedging EA"
#define EA_VERSION        "1.00"
#define EA_COPYRIGHT      "2024"

// Default symbol names (without suffix)
#define DEFAULT_SYMBOL_AUDCAD   "AUDCAD"
#define DEFAULT_SYMBOL_NZDCAD   "NZDCAD"
#define DEFAULT_SYMBOL_AUDNZD   "AUDNZD"

// Log file prefix
#define LOG_FILE_PREFIX   "DBasket_"

// Position comment prefix
#define BASKET_COMMENT_PREFIX   "DBasket_"

#endif // DBASKET_DEFINES_MQH
//+------------------------------------------------------------------+
