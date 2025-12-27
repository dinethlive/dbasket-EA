//+------------------------------------------------------------------+
//|                                       DBasket_TradeWrapper.mqh   |
//|                                   D-Basket Correlation Hedging EA |
//|                                   Trade Execution Abstraction     |
//+------------------------------------------------------------------+
#property copyright "D-Basket EA"
#property version   "1.00"
#property strict

#ifndef DBASKET_TRADEWRAPPER_MQH
#define DBASKET_TRADEWRAPPER_MQH

#include <Trade\Trade.mqh>
#include "DBasket_Defines.mqh"
#include "DBasket_Structures.mqh"
#include "DBasket_Logger.mqh"

//+------------------------------------------------------------------+
//| Trade Wrapper Class                                               |
//| Centralized trade execution with error handling and retry logic   |
//+------------------------------------------------------------------+
class CTradeWrapper
{
private:
   CTrade            m_trade;                // MQL5 trade object
   int               m_magicNumber;          // EA magic number
   int               m_slippagePoints;       // Maximum slippage
   int               m_maxRetries;           // Maximum retry attempts
   bool              m_isInitialized;
   
   // Statistics
   int               m_totalOrders;
   int               m_successfulOrders;
   int               m_failedOrders;
   int               m_retriedOrders;
   
   //+------------------------------------------------------------------+
   //| Check if error is retriable                                       |
   //+------------------------------------------------------------------+
   bool IsRetriableError(uint retcode)
   {
      switch(retcode)
      {
         case TRADE_RETCODE_REQUOTE:
         case TRADE_RETCODE_PRICE_OFF:
         case TRADE_RETCODE_PRICE_CHANGED:
         case TRADE_RETCODE_TIMEOUT:
         case TRADE_RETCODE_CONNECTION:
         case TRADE_RETCODE_SERVER_DISABLES_AT:
            return true;
         default:
            return false;
      }
   }
   
   //+------------------------------------------------------------------+
   //| Wait between retries                                              |
   //+------------------------------------------------------------------+
   void WaitForRetry(int attempt)
   {
      int waitMs = RETRY_DELAY_MS * (attempt + 1); // Exponential backoff
      Sleep(waitMs);
   }
   
   //+------------------------------------------------------------------+
   //| Check pre-trade conditions                                        |
   //+------------------------------------------------------------------+
   bool PreTradeCheck(string symbol, double lots, string &failReason)
   {
      // Check symbol tradability
      ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
      if(tradeMode != SYMBOL_TRADE_MODE_FULL)
      {
         failReason = "Symbol " + symbol + " is not fully tradeable. Mode: " + EnumToString(tradeMode);
         return false;
      }
      
      // Check volume constraints
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      
      if(lots < minLot)
      {
         failReason = "Lot size " + DoubleToString(lots, 2) + " below minimum " + DoubleToString(minLot, 2);
         return false;
      }
      
      if(lots > maxLot)
      {
         failReason = "Lot size " + DoubleToString(lots, 2) + " exceeds maximum " + DoubleToString(maxLot, 2);
         return false;
      }
      
      // Check margin
      double marginRequired;
      double price = SymbolInfoDouble(symbol, SYMBOL_ASK);
      
      if(!OrderCalcMargin(ORDER_TYPE_BUY, symbol, lots, price, marginRequired))
      {
         failReason = "Failed to calculate margin requirement";
         return false;
      }
      
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      
      if(freeMargin < marginRequired * 1.5) // 50% buffer
      {
         failReason = "Insufficient margin. Required: " + DoubleToString(marginRequired, 2) +
                     ", Available: " + DoubleToString(freeMargin, 2);
         return false;
      }
      
      return true;
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CTradeWrapper()
   {
      m_magicNumber = 100000;
      m_slippagePoints = DEFAULT_SLIPPAGE_POINTS;
      m_maxRetries = MAX_RETRY_ATTEMPTS;
      m_isInitialized = false;
      m_totalOrders = 0;
      m_successfulOrders = 0;
      m_failedOrders = 0;
      m_retriedOrders = 0;
   }
   
   //+------------------------------------------------------------------+
   //| Initialize trade wrapper                                          |
   //+------------------------------------------------------------------+
   bool Initialize(int magicNumber, int slippagePoints = DEFAULT_SLIPPAGE_POINTS, int maxRetries = MAX_RETRY_ATTEMPTS)
   {
      m_magicNumber = magicNumber;
      m_slippagePoints = slippagePoints;
      m_maxRetries = maxRetries;
      
      // Configure CTrade
      m_trade.SetExpertMagicNumber(m_magicNumber);
      m_trade.SetDeviationInPoints(m_slippagePoints);
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      m_trade.SetAsyncMode(false); // Synchronous mode for reliable basket execution
      
      m_isInitialized = true;
      
      Logger.Info("Trade Wrapper initialized - Magic: " + IntegerToString(m_magicNumber) +
                 ", Slippage: " + IntegerToString(m_slippagePoints) + " points");
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Open a position with retry logic                                  |
   //+------------------------------------------------------------------+
   bool OpenPosition(string symbol, ENUM_ORDER_TYPE orderType, double lots, 
                    string comment, ulong &ticket, string &errorMsg)
   {
      ticket = 0;
      errorMsg = "";
      m_totalOrders++;
      
      // Pre-trade validation
      if(!PreTradeCheck(symbol, lots, errorMsg))
      {
         Logger.Error("Pre-trade check failed: " + errorMsg);
         m_failedOrders++;
         return false;
      }
      
      // Get current price
      double price = (orderType == ORDER_TYPE_BUY) ? 
                     SymbolInfoDouble(symbol, SYMBOL_ASK) : 
                     SymbolInfoDouble(symbol, SYMBOL_BID);
      
      if(price == 0)
      {
         errorMsg = "Invalid price for " + symbol;
         m_failedOrders++;
         return false;
      }
      
      // Execute with retry logic
      for(int attempt = 0; attempt < m_maxRetries; attempt++)
      {
         // Refresh price on retry
         if(attempt > 0)
         {
            WaitForRetry(attempt);
            price = (orderType == ORDER_TYPE_BUY) ? 
                    SymbolInfoDouble(symbol, SYMBOL_ASK) : 
                    SymbolInfoDouble(symbol, SYMBOL_BID);
            m_retriedOrders++;
            Logger.Debug("Retrying order - Attempt " + IntegerToString(attempt + 1));
         }
         
         // Attempt to open position
         bool result = m_trade.PositionOpen(symbol, orderType, lots, price, 0, 0, comment);
         
         uint retcode = m_trade.ResultRetcode();
         
         if(result && retcode == TRADE_RETCODE_DONE)
         {
            ticket = m_trade.ResultOrder();
            m_successfulOrders++;
            
            Logger.Info("Position opened - Symbol: " + symbol +
                       ", Type: " + (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL") +
                       ", Lots: " + DoubleToString(lots, 2) +
                       ", Price: " + DoubleToString(m_trade.ResultPrice(), 5) +
                       ", Ticket: " + IntegerToString(ticket));
            
            return true;
         }
         
         // Check if error is retriable
         if(!IsRetriableError(retcode))
         {
            errorMsg = Logger.ErrorDescription((int)retcode);
            Logger.TradeError("OpenPosition", symbol, (int)retcode);
            break;
         }
         
         Logger.Debug("Retriable error: " + Logger.ErrorDescription((int)retcode));
      }
      
      m_failedOrders++;
      
      if(errorMsg == "")
         errorMsg = "Max retries exceeded";
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Close a position by ticket                                        |
   //+------------------------------------------------------------------+
   bool ClosePosition(ulong ticket, string &errorMsg)
   {
      errorMsg = "";
      
      // Select position
      if(!PositionSelectByTicket(ticket))
      {
         errorMsg = "Position not found: " + IntegerToString(ticket);
         return false;
      }
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      double lots = PositionGetDouble(POSITION_VOLUME);
      
      // Execute with retry logic
      for(int attempt = 0; attempt < m_maxRetries; attempt++)
      {
         if(attempt > 0)
         {
            WaitForRetry(attempt);
            m_retriedOrders++;
         }
         
         bool result = m_trade.PositionClose(ticket);
         uint retcode = m_trade.ResultRetcode();
         
         if(result && retcode == TRADE_RETCODE_DONE)
         {
            Logger.Info("Position closed - Ticket: " + IntegerToString(ticket) +
                       ", Symbol: " + symbol +
                       ", Lots: " + DoubleToString(lots, 2));
            return true;
         }
         
         if(!IsRetriableError(retcode))
         {
            errorMsg = Logger.ErrorDescription((int)retcode);
            Logger.TradeError("ClosePosition", symbol, (int)retcode);
            break;
         }
      }
      
      if(errorMsg == "")
         errorMsg = "Max retries exceeded";
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Close all positions by magic number                               |
   //+------------------------------------------------------------------+
   int CloseAllPositions(string &errorMsg)
   {
      int closed = 0;
      int total = PositionsTotal();
      
      // Close from end to avoid index shifting
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
            
         if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber)
            continue;
         
         string closeError;
         if(ClosePosition(ticket, closeError))
            closed++;
         else
            Logger.Error("Failed to close position " + IntegerToString(ticket) + ": " + closeError);
      }
      
      if(closed < total)
         errorMsg = "Closed " + IntegerToString(closed) + " of " + IntegerToString(total) + " positions";
      
      return closed;
   }
   
   //+------------------------------------------------------------------+
   //| Get position P&L by ticket                                        |
   //+------------------------------------------------------------------+
   double GetPositionProfit(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket))
         return 0;
         
      return PositionGetDouble(POSITION_PROFIT) + 
             PositionGetDouble(POSITION_SWAP);
   }
   
   //+------------------------------------------------------------------+
   //| Check if position exists                                          |
   //+------------------------------------------------------------------+
   bool PositionExists(ulong ticket)
   {
      return PositionSelectByTicket(ticket);
   }
   
   //+------------------------------------------------------------------+
   //| Normalize lot size to broker requirements                         |
   //+------------------------------------------------------------------+
   double NormalizeLots(string symbol, double lots)
   {
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      
      lots = MathMax(minLot, lots);
      lots = MathMin(maxLot, lots);
      lots = MathFloor(lots / lotStep) * lotStep;
      
      return NormalizeDouble(lots, 2);
   }
   
   //+------------------------------------------------------------------+
   //| Get execution statistics                                          |
   //+------------------------------------------------------------------+
   void GetStatistics(int &total, int &successful, int &failed, int &retried)
   {
      total = m_totalOrders;
      successful = m_successfulOrders;
      failed = m_failedOrders;
      retried = m_retriedOrders;
   }
   
   //+------------------------------------------------------------------+
   //| Get magic number                                                  |
   //+------------------------------------------------------------------+
   int GetMagicNumber() const
   {
      return m_magicNumber;
   }
   
   //+------------------------------------------------------------------+
   //| Count positions by magic number                                   |
   //+------------------------------------------------------------------+
   int CountPositions()
   {
      int count = 0;
      int total = PositionsTotal();
      
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
            
         if(PositionGetInteger(POSITION_MAGIC) == m_magicNumber)
            count++;
      }
      
      return count;
   }
};

#endif // DBASKET_TRADEWRAPPER_MQH
//+------------------------------------------------------------------+
