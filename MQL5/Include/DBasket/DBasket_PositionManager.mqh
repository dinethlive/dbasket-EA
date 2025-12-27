//+------------------------------------------------------------------+
//|                                     DBasket_PositionManager.mqh  |
//|                                   D-Basket Correlation Hedging EA |
//|                                   Basket Position Management      |
//+------------------------------------------------------------------+
#property copyright "D-Basket EA"
#property version   "1.00"
#property strict

#ifndef DBASKET_POSITIONMANAGER_MQH
#define DBASKET_POSITIONMANAGER_MQH

#include "DBasket_Defines.mqh"
#include "DBasket_Structures.mqh"
#include "DBasket_Logger.mqh"
#include "DBasket_TradeWrapper.mqh"

//+------------------------------------------------------------------+
//| Position Manager Class                                            |
//| Manages coordinated 3-leg basket positions                        |
//+------------------------------------------------------------------+
class CPositionManager
{
private:
   // Configuration
   string            m_symbols[NUM_SYMBOLS];
   double            m_baseLotSize;
   double            m_riskPercentPerBasket;
   ENUM_SIZING_MODE  m_sizingMode;
   int               m_maxOpenBaskets;
   int               m_maxHoldingHours;
   double            m_takeProfitAmount;
   double            m_stopLossAmount;
   
   // References
   CTradeWrapper*    m_tradeWrapper;
   
   // State
   BasketState       m_activeBasket;
   int               m_basketCounter;
   bool              m_isInitialized;
   
   //+------------------------------------------------------------------+
   //| Calculate lot size based on sizing mode                           |
   //+------------------------------------------------------------------+
   double CalculateLotSize(string symbol)
   {
      double lots = m_baseLotSize;
      
      if(m_sizingMode == SIZING_RISK_BASED)
      {
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         double riskAmount = equity * (m_riskPercentPerBasket / 100.0);
         
         // Divide by 3 for basket (each leg gets 1/3)
         double riskPerLeg = riskAmount / 3.0;
         
         // Use fixed pip stop assumption (e.g., 50 pips worst case)
         double pipValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE) * 10; // Approximate
         double stopPips = 50.0;
         
         if(pipValue > 0)
         {
            lots = riskPerLeg / (stopPips * pipValue);
         }
      }
      
      // Normalize lots to broker requirements
      return m_tradeWrapper.NormalizeLots(symbol, lots);
   }
   
   //+------------------------------------------------------------------+
   //| Get order types for basket direction                              |
   //+------------------------------------------------------------------+
   void GetBasketOrderTypes(ENUM_BASKET_SIGNAL direction, ENUM_ORDER_TYPE &types[])
   {
      if(ArrayResize(types, NUM_SYMBOLS) != NUM_SYMBOLS)
         return;
         
      if(direction == SIGNAL_LONG_BASKET)
      {
         // Long basket: expect AUDNZD to rise
         // Trade: Long AUDNZD, Short AUDCAD, Long NZDCAD
         types[SYMBOL_AUDCAD] = ORDER_TYPE_SELL;  // Short AUDCAD
         types[SYMBOL_NZDCAD] = ORDER_TYPE_BUY;   // Long NZDCAD
         types[SYMBOL_AUDNZD] = ORDER_TYPE_BUY;   // Long AUDNZD
      }
      else if(direction == SIGNAL_SHORT_BASKET)
      {
         // Short basket: expect AUDNZD to fall
         // Trade: Short AUDNZD, Long AUDCAD, Short NZDCAD
         types[SYMBOL_AUDCAD] = ORDER_TYPE_BUY;   // Long AUDCAD
         types[SYMBOL_NZDCAD] = ORDER_TYPE_SELL;  // Short NZDCAD
         types[SYMBOL_AUDNZD] = ORDER_TYPE_SELL;  // Short AUDNZD
      }
   }
   
   //+------------------------------------------------------------------+
   //| Close specific legs (for rollback)                                |
   //+------------------------------------------------------------------+
   bool CloseLegs(int upToIndex)
   {
      bool allClosed = true;
      
      for(int i = 0; i <= upToIndex; i++)
      {
         if(m_activeBasket.positions[i].isOpen)
         {
            string errorMsg;
            if(!m_tradeWrapper.ClosePosition(m_activeBasket.positions[i].ticket, errorMsg))
            {
               Logger.Error("Failed to close leg " + IntegerToString(i) + ": " + errorMsg);
               allClosed = false;
            }
            else
            {
               m_activeBasket.positions[i].isOpen = false;
            }
         }
      }
      
      return allClosed;
   }
   
   //+------------------------------------------------------------------+
   //| Update position P&L for a single position                         |
   //+------------------------------------------------------------------+
   void UpdatePositionPL(int index)
   {
      if(!m_activeBasket.positions[index].isOpen)
         return;
         
      ulong ticket = m_activeBasket.positions[index].ticket;
      
      if(PositionSelectByTicket(ticket))
      {
         m_activeBasket.positions[index].unrealizedPL = 
            PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         m_activeBasket.positions[index].currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         m_activeBasket.positions[index].swap = PositionGetDouble(POSITION_SWAP);
         // Note: POSITION_COMMISSION is deprecated in MQL5 and returns 0
         // Commission is now tracked via deal history (DEAL_COMMISSION)
         // For live P&L, commission is already factored into POSITION_PROFIT by most brokers
         m_activeBasket.positions[index].commission = 0;
      }
      else
      {
         // Position no longer exists
         m_activeBasket.positions[index].isOpen = false;
         Logger.Warning("Position " + IntegerToString(ticket) + " no longer exists");
      }
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CPositionManager()
   {
      m_baseLotSize = 0.01;
      m_riskPercentPerBasket = 1.0;
      m_sizingMode = SIZING_FIXED;
      m_maxOpenBaskets = 1;
      m_maxHoldingHours = DEFAULT_MAX_HOLDING_HOURS;
      m_takeProfitAmount = 0;
      m_stopLossAmount = 0;
      m_tradeWrapper = NULL;
      m_basketCounter = 0;
      m_isInitialized = false;
      
      for(int i = 0; i < NUM_SYMBOLS; i++)
         m_symbols[i] = "";
         
      m_activeBasket.Reset();
   }
   
   //+------------------------------------------------------------------+
   //| Initialize position manager                                       |
   //+------------------------------------------------------------------+
   bool Initialize(const EAConfig &config, CTradeWrapper *tradeWrapper)
   {
      if(tradeWrapper == NULL)
      {
         Logger.Error("Trade wrapper is NULL");
         return false;
      }
      
      m_tradeWrapper = tradeWrapper;
      
      // Copy configuration
      for(int i = 0; i < NUM_SYMBOLS; i++)
         m_symbols[i] = config.symbols[i];
         
      m_baseLotSize = config.baseLotSize;
      m_riskPercentPerBasket = config.riskPercentPerBasket;
      m_sizingMode = config.sizingMode;
      m_maxOpenBaskets = config.maxOpenBaskets;
      m_maxHoldingHours = config.maxHoldingHours;
      
      // Calculate TP/SL amounts (e.g., 2x average expected profit)
      m_takeProfitAmount = 10.0;  // Default $10, can be made configurable
      m_stopLossAmount = 15.0;    // Default $15, can be made configurable
      
      m_isInitialized = true;
      m_activeBasket.Reset();
      
      Logger.Info("Position Manager initialized - Base Lot: " + DoubleToString(m_baseLotSize, 2) +
                 ", Sizing: " + EnumToString(m_sizingMode));
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Open a new basket (coordinated 3-leg entry)                       |
   //+------------------------------------------------------------------+
   bool OpenBasket(ENUM_BASKET_SIGNAL direction, double zScore, double correlation)
   {
      if(!m_isInitialized || m_tradeWrapper == NULL)
      {
         Logger.Error("Position Manager not initialized");
         return false;
      }
      
      if(HasOpenBasket())
      {
         Logger.Warning("Cannot open new basket - basket already open");
         return false;
      }
      
      if(direction != SIGNAL_LONG_BASKET && direction != SIGNAL_SHORT_BASKET)
      {
         Logger.Error("Invalid basket direction");
         return false;
      }
      
      // Reset basket state
      m_activeBasket.Reset();
      m_basketCounter++;
      m_activeBasket.basketID = m_basketCounter;
      m_activeBasket.direction = direction;
      m_activeBasket.openTime = TimeCurrent();
      m_activeBasket.entryZScore = zScore;
      m_activeBasket.entryCorrelation = correlation;
      m_activeBasket.state = BASKET_ENTRY_PENDING;
      
      // Get order types for each leg
      ENUM_ORDER_TYPE orderTypes[];
      GetBasketOrderTypes(direction, orderTypes);
      
      // Calculate lot sizes
      double lotSizes[];
      ArrayResize(lotSizes, NUM_SYMBOLS);
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         lotSizes[i] = CalculateLotSize(m_symbols[i]);
      }
      
      Logger.Info("Opening basket #" + IntegerToString(m_activeBasket.basketID) +
                 " - Direction: " + (direction == SIGNAL_LONG_BASKET ? "LONG" : "SHORT"));
      
      // Execute legs sequentially (AUDNZD first as reference)
      int executionOrder[] = {SYMBOL_AUDNZD, SYMBOL_AUDCAD, SYMBOL_NZDCAD};
      
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         int legIndex = executionOrder[i];
         string symbol = m_symbols[legIndex];
         ENUM_ORDER_TYPE orderType = orderTypes[legIndex];
         double lots = lotSizes[legIndex];
         
         string comment = BASKET_COMMENT_PREFIX + IntegerToString(m_activeBasket.basketID);
         ulong ticket = 0;
         string errorMsg;
         
         bool success = m_tradeWrapper.OpenPosition(symbol, orderType, lots, comment, ticket, errorMsg);
         
         if(success)
         {
            // Record position
            m_activeBasket.positions[legIndex].ticket = ticket;
            m_activeBasket.positions[legIndex].symbol = symbol;
            m_activeBasket.positions[legIndex].symbolIndex = legIndex;
            m_activeBasket.positions[legIndex].type = (ENUM_POSITION_TYPE)orderType;
            m_activeBasket.positions[legIndex].lots = lots;
            m_activeBasket.positions[legIndex].openPrice = SymbolInfoDouble(symbol, 
               orderType == ORDER_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
            m_activeBasket.positions[legIndex].openTime = TimeCurrent();
            m_activeBasket.positions[legIndex].isOpen = true;
            m_activeBasket.positions[legIndex].comment = comment;
            
            Logger.Debug("Leg " + IntegerToString(legIndex) + " opened - " + symbol +
                        " " + (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL") +
                        " " + DoubleToString(lots, 2) + " lots");
         }
         else
         {
            Logger.Error("Failed to open leg " + IntegerToString(legIndex) + " (" + symbol + "): " + errorMsg);
            
            // Rollback: close any legs that were opened
            if(i > 0)
            {
               Logger.Warning("Rolling back partial basket - closing opened legs");
               for(int j = 0; j < i; j++)
               {
                  int rollbackIndex = executionOrder[j];
                  if(m_activeBasket.positions[rollbackIndex].isOpen)
                  {
                     string closeError;
                     m_tradeWrapper.ClosePosition(m_activeBasket.positions[rollbackIndex].ticket, closeError);
                  }
               }
            }
            
            m_activeBasket.Reset();
            return false;
         }
      }
      
      // All legs opened successfully
      m_activeBasket.state = BASKET_OPEN;
      m_activeBasket.lastUpdateTime = TimeCurrent();
      
      Logger.LogBasketOpen(m_activeBasket.basketID, direction, zScore, correlation);
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Close the active basket                                           |
   //+------------------------------------------------------------------+
   bool CloseBasket(ENUM_EXIT_REASON reason)
   {
      if(!HasOpenBasket())
      {
         Logger.Debug("No basket to close");
         return true;
      }
      
      m_activeBasket.state = BASKET_EXIT_PENDING;
      m_activeBasket.exitReason = reason;
      
      Logger.Info("Closing basket #" + IntegerToString(m_activeBasket.basketID) +
                 " - Reason: " + EnumToString(reason));
      
      bool allClosed = true;
      double totalPL = 0;
      
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         if(!m_activeBasket.positions[i].isOpen)
            continue;
            
         ulong ticket = m_activeBasket.positions[i].ticket;
         
         // Get P&L before closing
         double pl = m_tradeWrapper.GetPositionProfit(ticket);
         totalPL += pl;
         
         string errorMsg;
         if(m_tradeWrapper.ClosePosition(ticket, errorMsg))
         {
            m_activeBasket.positions[i].isOpen = false;
            m_activeBasket.positions[i].unrealizedPL = pl;
         }
         else
         {
            Logger.Error("Failed to close position " + IntegerToString(ticket) + ": " + errorMsg);
            allClosed = false;
         }
      }
      
      if(allClosed)
      {
         m_activeBasket.realizedPL = totalPL;
         m_activeBasket.state = BASKET_CLOSED;
         
         Logger.LogBasketClose(m_activeBasket.basketID, reason, totalPL, m_activeBasket.barsHeld);
         
         // Reset basket state for next trade
         m_activeBasket.Reset();
      }
      else
      {
         m_activeBasket.state = BASKET_PARTIAL;
         Logger.Error("Basket partially closed - manual intervention may be required");
      }
      
      return allClosed;
   }
   
   //+------------------------------------------------------------------+
   //| Update basket state and P&L                                       |
   //+------------------------------------------------------------------+
   void UpdateBasketState()
   {
      if(!HasOpenBasket())
         return;
         
      double totalPL = 0;
      int openCount = 0;
      
      for(int i = 0; i < NUM_SYMBOLS; i++)
      {
         if(m_activeBasket.positions[i].isOpen)
         {
            UpdatePositionPL(i);
            
            if(m_activeBasket.positions[i].isOpen) // Check again after update
            {
               totalPL += m_activeBasket.positions[i].unrealizedPL;
               openCount++;
            }
         }
      }
      
      m_activeBasket.unrealizedPL = totalPL;
      m_activeBasket.lastUpdateTime = TimeCurrent();
      
      // Update basket state based on open positions
      if(openCount == 0)
      {
         Logger.Warning("All positions closed externally - resetting basket");
         m_activeBasket.Reset();
      }
      else if(openCount < NUM_SYMBOLS && m_activeBasket.state == BASKET_OPEN)
      {
         Logger.Warning("Basket is now partial - " + IntegerToString(openCount) + " legs open");
         m_activeBasket.state = BASKET_PARTIAL;
      }
   }
   
   //+------------------------------------------------------------------+
   //| Check if basket is open                                           |
   //+------------------------------------------------------------------+
   bool HasOpenBasket()
   {
      return m_activeBasket.IsActive();
   }
   
   //+------------------------------------------------------------------+
   //| Get current basket state                                          |
   //+------------------------------------------------------------------+
   void GetBasketState(BasketState &state)
   {
      state = m_activeBasket;
   }
   
   //+------------------------------------------------------------------+
   //| Get basket unrealized P&L                                         |
   //+------------------------------------------------------------------+
   double GetBasketPL()
   {
      return m_activeBasket.unrealizedPL;
   }
   
   //+------------------------------------------------------------------+
   //| Get current basket direction                                      |
   //+------------------------------------------------------------------+
   ENUM_BASKET_SIGNAL GetBasketDirection()
   {
      return m_activeBasket.direction;
   }
   
   //+------------------------------------------------------------------+
   //| Get take profit amount                                            |
   //+------------------------------------------------------------------+
   double GetTakeProfitAmount()
   {
      return m_takeProfitAmount;
   }
   
   //+------------------------------------------------------------------+
   //| Get stop loss amount                                              |
   //+------------------------------------------------------------------+
   double GetStopLossAmount()
   {
      return m_stopLossAmount;
   }
   
   //+------------------------------------------------------------------+
   //| Get max holding hours                                             |
   //+------------------------------------------------------------------+
   int GetMaxHoldingHours()
   {
      return m_maxHoldingHours;
   }
   
   //+------------------------------------------------------------------+
   //| Set TP/SL amounts                                                 |
   //+------------------------------------------------------------------+
   void SetTPSL(double takeProfitAmount, double stopLossAmount)
   {
      m_takeProfitAmount = takeProfitAmount;
      m_stopLossAmount = stopLossAmount;
   }
   
   //+------------------------------------------------------------------+
   //| Recover basket state from open positions                          |
   //+------------------------------------------------------------------+
   void RecoverFromOpenPositions()
   {
      int magicNumber = m_tradeWrapper.GetMagicNumber();
      int positionsFound = 0;
      
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
            
         if(PositionGetInteger(POSITION_MAGIC) != magicNumber)
            continue;
            
         string symbol = PositionGetString(POSITION_SYMBOL);
         
         // Find symbol index
         int symbolIndex = -1;
         for(int j = 0; j < NUM_SYMBOLS; j++)
         {
            if(symbol == m_symbols[j])
            {
               symbolIndex = j;
               break;
            }
         }
         
         if(symbolIndex >= 0)
         {
            m_activeBasket.positions[symbolIndex].ticket = ticket;
            m_activeBasket.positions[symbolIndex].symbol = symbol;
            m_activeBasket.positions[symbolIndex].symbolIndex = symbolIndex;
            m_activeBasket.positions[symbolIndex].type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            m_activeBasket.positions[symbolIndex].lots = PositionGetDouble(POSITION_VOLUME);
            m_activeBasket.positions[symbolIndex].openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            m_activeBasket.positions[symbolIndex].openTime = (datetime)PositionGetInteger(POSITION_TIME);
            m_activeBasket.positions[symbolIndex].isOpen = true;
            m_activeBasket.positions[symbolIndex].comment = PositionGetString(POSITION_COMMENT);
            
            positionsFound++;
         }
      }
      
      if(positionsFound > 0)
      {
         Logger.Info("Recovered " + IntegerToString(positionsFound) + " positions from previous session");
         
         if(positionsFound == NUM_SYMBOLS)
         {
            m_activeBasket.state = BASKET_OPEN;
            // Try to determine direction from position types
            if(m_activeBasket.positions[SYMBOL_AUDNZD].type == POSITION_TYPE_BUY)
               m_activeBasket.direction = SIGNAL_LONG_BASKET;
            else
               m_activeBasket.direction = SIGNAL_SHORT_BASKET;
         }
         else
         {
            m_activeBasket.state = BASKET_PARTIAL;
            Logger.Warning("Incomplete basket recovered - may need manual intervention");
         }
         
         m_activeBasket.basketID = ++m_basketCounter;
         m_activeBasket.openTime = m_activeBasket.positions[0].openTime;
         m_activeBasket.lastUpdateTime = TimeCurrent();
      }
   }
};

#endif // DBASKET_POSITIONMANAGER_MQH
//+------------------------------------------------------------------+
