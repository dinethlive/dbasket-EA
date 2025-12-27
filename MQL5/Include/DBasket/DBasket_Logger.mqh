//+------------------------------------------------------------------+
//|                                              DBasket_Logger.mqh  |
//|                                   D-Basket Correlation Hedging EA |
//|                                   Logging Utility                 |
//+------------------------------------------------------------------+
#property copyright "D-Basket EA"
#property version   "1.00"
#property strict

#ifndef DBASKET_LOGGER_MQH
#define DBASKET_LOGGER_MQH

#include "DBasket_Defines.mqh"

//+------------------------------------------------------------------+
//| Logger Class                                                      |
//| Centralized logging with configurable levels and file output      |
//+------------------------------------------------------------------+
class CLogger
{
private:
   ENUM_LOG_LEVEL    m_logLevel;             // Current log level
   bool              m_logToFile;            // Enable file logging
   int               m_fileHandle;           // Log file handle
   string            m_logFileName;          // Log file name
   bool              m_isInitialized;        // Initialization status
   
   // Format timestamp for logging
   string FormatTimestamp(datetime time)
   {
      return TimeToString(time, TIME_DATE | TIME_SECONDS);
   }
   
   // Get log level string
   string GetLevelString(ENUM_LOG_LEVEL level)
   {
      switch(level)
      {
         case LOG_LEVEL_ERROR:   return "[ERROR]";
         case LOG_LEVEL_WARNING: return "[WARN] ";
         case LOG_LEVEL_INFO:    return "[INFO] ";
         case LOG_LEVEL_DEBUG:   return "[DEBUG]";
         default:                return "[????] ";
      }
   }
   
   // Write to file if enabled
   void WriteToFile(string message)
   {
      if(!m_logToFile || m_fileHandle == INVALID_HANDLE)
         return;
         
      FileWriteString(m_fileHandle, message + "\n");
      FileFlush(m_fileHandle);
   }
   
public:
   // Constructor
   CLogger()
   {
      m_logLevel = LOG_LEVEL_INFO;
      m_logToFile = false;
      m_fileHandle = INVALID_HANDLE;
      m_logFileName = "";
      m_isInitialized = false;
   }
   
   // Destructor
   ~CLogger()
   {
      Deinitialize();
   }
   
   //+------------------------------------------------------------------+
   //| Initialize logger                                                 |
   //+------------------------------------------------------------------+
   bool Initialize(ENUM_LOG_LEVEL level, bool logToFile = false)
   {
      m_logLevel = level;
      m_logToFile = logToFile;
      
      if(logToFile)
      {
         // Create log file with timestamp
         m_logFileName = LOG_FILE_PREFIX + TimeToString(TimeCurrent(), TIME_DATE) + ".log";
         StringReplace(m_logFileName, ".", "_");
         StringReplace(m_logFileName, ":", "_");
         m_logFileName = m_logFileName + ".log";
         
         m_fileHandle = FileOpen(m_logFileName, FILE_WRITE | FILE_READ | FILE_TXT | FILE_SHARE_READ);
         
         if(m_fileHandle == INVALID_HANDLE)
         {
            Print("Logger: Failed to open log file: ", m_logFileName, " Error: ", GetLastError());
            m_logToFile = false;
         }
         else
         {
            // Move to end of file for appending
            FileSeek(m_fileHandle, 0, SEEK_END);
         }
      }
      
      m_isInitialized = true;
      Info("Logger initialized - Level: " + EnumToString(level) + ", File: " + (logToFile ? m_logFileName : "Disabled"));
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Deinitialize logger                                               |
   //+------------------------------------------------------------------+
   void Deinitialize()
   {
      if(m_fileHandle != INVALID_HANDLE)
      {
         FileClose(m_fileHandle);
         m_fileHandle = INVALID_HANDLE;
      }
      m_isInitialized = false;
   }
   
   //+------------------------------------------------------------------+
   //| Set log level                                                     |
   //+------------------------------------------------------------------+
   void SetLogLevel(ENUM_LOG_LEVEL level)
   {
      m_logLevel = level;
   }
   
   //+------------------------------------------------------------------+
   //| Core logging function                                             |
   //+------------------------------------------------------------------+
   void Log(ENUM_LOG_LEVEL level, string message)
   {
      // Check if this level should be logged
      if(level > m_logLevel)
         return;
         
      // Format message
      string timestamp = FormatTimestamp(TimeCurrent());
      string levelStr = GetLevelString(level);
      string fullMessage = timestamp + " " + levelStr + " " + message;
      
      // Output to terminal
      Print(fullMessage);
      
      // Output to file if enabled
      WriteToFile(fullMessage);
   }
   
   //+------------------------------------------------------------------+
   //| Convenience methods                                               |
   //+------------------------------------------------------------------+
   void Error(string message)
   {
      Log(LOG_LEVEL_ERROR, message);
   }
   
   void Warning(string message)
   {
      Log(LOG_LEVEL_WARNING, message);
   }
   
   void Info(string message)
   {
      Log(LOG_LEVEL_INFO, message);
   }
   
   void Debug(string message)
   {
      Log(LOG_LEVEL_DEBUG, message);
   }
   
   //+------------------------------------------------------------------+
   //| Log with formatting (variadic-like using overloads)               |
   //+------------------------------------------------------------------+
   void ErrorF(string format, string arg1)
   {
      string msg = format;
      StringReplace(msg, "%s", arg1);
      Error(msg);
   }
   
   void ErrorF(string format, string arg1, string arg2)
   {
      string msg = format;
      StringReplace(msg, "%s", arg1);
      StringReplace(msg, "%s", arg2);
      Error(msg);
   }
   
   void InfoF(string format, string arg1)
   {
      string msg = format;
      StringReplace(msg, "%s", arg1);
      Info(msg);
   }
   
   void InfoF(string format, double value)
   {
      string msg = format;
      StringReplace(msg, "%.2f", DoubleToString(value, 2));
      StringReplace(msg, "%.4f", DoubleToString(value, 4));
      StringReplace(msg, "%.5f", DoubleToString(value, 5));
      StringReplace(msg, "%f", DoubleToString(value, 5));
      Info(msg);
   }
   
   void DebugF(string format, string arg1)
   {
      string msg = format;
      StringReplace(msg, "%s", arg1);
      Debug(msg);
   }
   
   void DebugF(string format, double value)
   {
      string msg = format;
      StringReplace(msg, "%.2f", DoubleToString(value, 2));
      StringReplace(msg, "%.4f", DoubleToString(value, 4));
      StringReplace(msg, "%.5f", DoubleToString(value, 5));
      StringReplace(msg, "%f", DoubleToString(value, 5));
      Debug(msg);
   }
   
   //+------------------------------------------------------------------+
   //| Log trade error with context                                      |
   //+------------------------------------------------------------------+
   void TradeError(string operation, string symbol, int errorCode)
   {
      string errorDesc = ErrorDescription(errorCode);
      Error("Trade Error - Op: " + operation + 
            ", Symbol: " + symbol + 
            ", Code: " + IntegerToString(errorCode) + 
            ", Desc: " + errorDesc);
   }
   
   //+------------------------------------------------------------------+
   //| Log basket state                                                  |
   //+------------------------------------------------------------------+
   void LogBasketOpen(int basketID, ENUM_BASKET_SIGNAL direction, double zScore, double correlation)
   {
      string dirStr = (direction == SIGNAL_LONG_BASKET) ? "LONG" : "SHORT";
      Info("Basket #" + IntegerToString(basketID) + " OPENED - " +
           "Direction: " + dirStr + 
           ", Z-Score: " + DoubleToString(zScore, 2) +
           ", Correlation: " + DoubleToString(correlation, 4));
   }
   
   void LogBasketClose(int basketID, ENUM_EXIT_REASON reason, double pl, int holdBars)
   {
      string reasonStr;
      switch(reason)
      {
         case EXIT_MEAN_REVERSION:    reasonStr = "Mean Reversion"; break;
         case EXIT_TAKE_PROFIT:       reasonStr = "Take Profit"; break;
         case EXIT_STOP_LOSS:         reasonStr = "Stop Loss"; break;
         case EXIT_MAX_TIME:          reasonStr = "Max Time"; break;
         case EXIT_CORRELATION_BREAK: reasonStr = "Correlation Break"; break;
         case EXIT_RISK_LIMIT:        reasonStr = "Risk Limit"; break;
         case EXIT_EMERGENCY:         reasonStr = "Emergency"; break;
         default:                     reasonStr = "Manual"; break;
      }
      
      Info("Basket #" + IntegerToString(basketID) + " CLOSED - " +
           "Reason: " + reasonStr +
           ", P/L: " + DoubleToString(pl, 2) +
           ", Bars Held: " + IntegerToString(holdBars));
   }
   
   //+------------------------------------------------------------------+
   //| Convert error code to description                                 |
   //+------------------------------------------------------------------+
   string ErrorDescription(int errorCode)
   {
      switch(errorCode)
      {
         case 0:     return "No error";
         case 10004: return "Requote";
         case 10006: return "Request rejected";
         case 10007: return "Request canceled by trader";
         case 10010: return "Only part of request completed";
         case 10011: return "Request processing error";
         case 10012: return "Request canceled by timeout";
         case 10013: return "Invalid request";
         case 10014: return "Invalid volume";
         case 10015: return "Invalid price";
         case 10016: return "Invalid stops";
         case 10017: return "Trade disabled";
         case 10018: return "Market closed";
         case 10019: return "Insufficient funds";
         case 10020: return "Prices changed";
         case 10021: return "No quotes";
         case 10022: return "Invalid order expiration";
         case 10023: return "Order state changed";
         case 10024: return "Too many requests";
         case 10025: return "No changes in request";
         case 10026: return "Autotrading disabled by server";
         case 10027: return "Autotrading disabled by client";
         case 10028: return "Request locked for processing";
         case 10029: return "Order or position frozen";
         case 10030: return "Invalid fill type";
         case 10031: return "No connection with trade server";
         case 10032: return "Operation allowed only for live accounts";
         case 10033: return "Pending orders limit reached";
         case 10034: return "Order or position volume limit reached";
         case 10035: return "Invalid or prohibited order type";
         case 10036: return "Position with specified POSITION_IDENTIFIER already closed";
         case 10038: return "Close volume exceeds current position volume";
         case 10039: return "Close order already exists";
         case 10040: return "Limit of pending orders reached";
         case 10041: return "Order or position modification rejected";
         case 10042: return "Request rejected by trade context busy";
         case 10043: return "Only part of positions closed";
         case 10044: return "Position limit reached";
         default:    return "Unknown error (" + IntegerToString(errorCode) + ")";
      }
   }
   
   //+------------------------------------------------------------------+
   //| Log initialization summary                                        |
   //+------------------------------------------------------------------+
   void LogInitSummary(string eaName, string version, double balance, int leverage, string server)
   {
      Info("==================================================");
      Info("= " + eaName + " v" + version);
      Info("==================================================");
      Info("Account Balance: " + DoubleToString(balance, 2));
      Info("Leverage: 1:" + IntegerToString(leverage));
      Info("Server: " + server);
      Info("==================================================");
   }
   
   //+------------------------------------------------------------------+
   //| Log correlation data                                              |
   //+------------------------------------------------------------------+
   void LogCorrelationData(const CorrelationData &data)
   {
      if(m_logLevel < LOG_LEVEL_DEBUG)
         return;
         
      Debug("Correlation Data - " +
            "Corr: " + DoubleToString(data.corrAUDCAD_NZDCAD, 4) +
            ", Ratio: " + DoubleToString(data.syntheticRatio, 5) +
            ", Actual: " + DoubleToString(data.actualAUDNZD, 5) +
            ", Spread: " + DoubleToString(data.spreadValue, 5) +
            ", Z: " + DoubleToString(data.spreadZScore, 2) +
            ", Valid: " + (data.isValid ? "Yes" : "No"));
   }
};

//+------------------------------------------------------------------+
//| Global logger instance                                            |
//+------------------------------------------------------------------+
CLogger Logger;

#endif // DBASKET_LOGGER_MQH
//+------------------------------------------------------------------+
