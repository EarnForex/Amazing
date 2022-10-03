//+------------------------------------------------------------------+
//|                                                          Amazing |
//|                             Copyright © 2008-2022, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//|                                 Based on the EA by FiFtHeLeMeNt. |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2008-2022, EarnForex"
#property link      "https://www.earnforex.com/metatrader-expert-advisors/Amazing/"
#property version   "1.03"

#property description "Amazing - EA that helps to trade on news."
#property description "Set the NewsDateTime input parameter to the actual date and time of the news."
#property description "EA will set up the pending orders (buy and sell) to be triggered by the news."
#property description "It will use a profit target, breakeven, and trailing stop to manage it."

#include <Trade/Trade.mqh>
#include <errordescription.mqh>

input group "Main"
input datetime NewsDateTime = __DATE__; // NewsDateTime: Date and time of the news release.
input int TP = 20; // TP: Take-profit
input int CTCBN = 0; // CTCBN: Number of candles to check before news for High & Low.
input int SecBPO = 300; // SecBPO: Seconds before news to place pending orders.
input int SecBMO = 0; // SecBMO: Seconds before news when to stop modifying orders.
input int STWAN = 150; // STWAN: Seconds to wait after news to delete pending orders.
input bool OCO = true; // OCO: EA will cancel the other pending order if one is hit.
input int BEPips = 0; // BEPips: Pips of profit when EA will move SL to breakeven + 1.
input int TrailingStop = 0; // Trailing Stop
input group "Money management"
input bool MM = false; // MM: Money management
input int RiskPercent = 1;
input double Lots = 0.1;
input group "Miscellaneous"
input int Slippage = 3;  // Slippage: Tolerated slippage in pips.
input string TradeLog = "Am_Log_"; // TradeLog: Log file prefix.
input string Commentary = "Amazing"; // Commentary: trade description.

// Global variables:
double buy_stop_entry, sell_stop_entry, buy_stop_loss, sell_stop_loss, buy_take_profit, sell_take_profit;
int Magic;
string filename;
double Poin;
int Deviation;

// Main trading objects:
CTrade *Trade;
CPositionInfo PositionInfo;
COrderInfo OrderInfo;

void OnInit()
{
    Magic = (int)NewsDateTime; // Dynamically generated Magic number to allow multiple instances for different news announcements.

    // Checking for unconventional Point digits number.
    if ((_Point == 0.00001) || (_Point == 0.001))
    {
        Poin = _Point * 10;
        Deviation = Slippage * 10;
    }
    else
    {
        Poin = _Point; // Normal
        Deviation = Slippage;
    }

    if (StringLen(Commentary) > 0)
    {
        MqlDateTime dt;
        TimeCurrent(dt);
        filename = TradeLog + Symbol() + "-" + IntegerToString(dt.mon) + "-" + IntegerToString(dt.day) + ".txt";
    }

    // Initialize the Trade class object
    Trade = new CTrade;
    Trade.SetDeviationInPoints(Deviation);
    Trade.SetExpertMagicNumber(Magic);
}

void OnDeinit(const int reason)
{
    Comment("");
    delete Trade;
}

//+------------------------------------------------------------------+
//| Returns lots number based on simple money management.            |
//+------------------------------------------------------------------+
double LotsOptimized()
{
    double lot = Lots;

    if (MM)
    {
        double LotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
        int LotStep_digits = CountDecimalPlaces(LotStep);
        lot = NormalizeDouble(MathFloor(AccountInfoDouble(ACCOUNT_MARGIN_FREE) * RiskPercent / 100) / 100, LotStep_digits);
    }

    // lot at this point is the number of standard lots.
    return lot;
}

// Checks the current situation with orders and positions.
//   Result Pattern
//   1    1    1    1
//   |    |    |    |
//   |    |    |    -------- Sell Stop Order
//   |    |    --------Buy Stop Order
//   |    --------Sell Position
//   --------Buy Position
int CheckOrdersCondition()
{
    int result = 0;

    // First, check orders.
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (!OrderSelect(OrderGetTicket(i)))
        {
            {
                Write(__FUNCTION__ + " | Error selecting an order: " + ErrorDescription(GetLastError()));
                continue;
            }
        }
        if ((OrderGetString(ORDER_SYMBOL) != Symbol()) || (OrderGetInteger(ORDER_MAGIC) != Magic)) continue;
        
        if (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP)
        {
            result = result + 10;
        }
        else if (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP)
        {
            result = result + 1;
        }
    }

    // Second, check positions.
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (!PositionSelectByTicket(PositionGetTicket(i)))
        {
            {
                Write(__FUNCTION__ + " | Error selecting a position: " + ErrorDescription(GetLastError()));
                continue;
            }
        }
        if ((PositionGetString(POSITION_SYMBOL) != Symbol()) || (PositionGetInteger(POSITION_MAGIC) != Magic)) continue;

        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            result = result + 1000;
        }
        else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            result = result + 100;
        }
    }
    return result; // 0 means there are no orders/positions.
}

void OpenBuyStop()
{
    for (int tries = 0; tries < 10; tries++)
    {
        Trade.OrderOpen(_Symbol, ORDER_TYPE_BUY_STOP, LotsOptimized(), 0, buy_stop_entry, buy_stop_loss, buy_take_profit, 0, 0, Commentary);
        ulong ticket = Trade.ResultOrder(); // Get ticket.
        if (ticket < 0)
        {
            Write("Error in OrderSend: " + ErrorDescription(GetLastError()) + " Buy Stop @ " + DoubleToString(buy_stop_entry, _Digits) + " SL @ " + DoubleToString(buy_stop_loss, _Digits) + " TP @" + DoubleToString(buy_take_profit, _Digits));
            tries++;
        }
        else
        {
            Write("Open Buy Stop: OrderSend executed. Ticket = " + IntegerToString(ticket));
            break;
        }
    }
}

void OpenSellStop()
{
    for (int tries = 0; tries < 10; tries++)
    {
        Trade.OrderOpen(_Symbol, ORDER_TYPE_SELL_STOP, LotsOptimized(), 0, sell_stop_entry, sell_stop_loss, sell_take_profit, 0, 0, Commentary);
        ulong ticket = Trade.ResultOrder(); // Get ticket.
        if (ticket < 0)
        {
            Write("Error in OrderSend: " + ErrorDescription(GetLastError()) + " Sell Stop @ " + DoubleToString(sell_stop_entry, _Digits) + " SL @ " + DoubleToString(sell_stop_loss, _Digits) + " TP @" + DoubleToString(sell_take_profit, _Digits));
        }
        else
        {
            Write("Open Sell Stop: OrderSend executed. Ticket = "  + IntegerToString(ticket));
            break;
        }
    }
}

// Set breakeven on positions if needed.
void DoBE(int byPips)
{
    double Ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double Bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (!PositionSelectByTicket(PositionGetTicket(i)))
        {
            {
                Write(__FUNCTION__ + " | Error selecting a position: " + ErrorDescription(GetLastError()));
                continue;
            }
        }
        if ((PositionGetString(POSITION_SYMBOL) != Symbol()) || (PositionGetInteger(POSITION_MAGIC) != Magic)) continue;
        
        if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) && (NormalizeDouble(Bid - PositionGetDouble(POSITION_PRICE_OPEN), _Digits) > NormalizeDouble(byPips * Poin, _Digits)) && (PositionInfo.StopLoss() < PositionGetDouble(POSITION_PRICE_OPEN)))
        {
            double NewSL = NormalizeDouble(PositionInfo.PriceOpen() + Poin, _Digits);
            if (Bid - NewSL > SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * _Point)
            {
                Write("Moving stop-loss of Buy order to breakeven + 1 pip.");
                if (!Trade.PositionModify(_Symbol, NewSL, PositionGetDouble(POSITION_TP)))
                {
                    Write(__FUNCTION__ + " | Error modifying Buy: " + ErrorDescription(GetLastError()));
                }
            }
        }
        else if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) && (NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN) - Ask, _Digits) > NormalizeDouble(byPips * Poin, _Digits)) && (PositionInfo.StopLoss() > PositionGetDouble(POSITION_PRICE_OPEN)))
        {
            double NewSL = NormalizeDouble(PositionInfo.PriceOpen() - Poin, _Digits);
            if (NewSL - Ask > SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * _Point)
            {
                Write("Moving stop-loss of Sell order to breakeven - 1 pip.");
                if (!Trade.PositionModify(_Symbol, NewSL, PositionGetDouble(POSITION_SL)))
                {
                    Write(__FUNCTION__ + " | Error modifying Sell: " + ErrorDescription(GetLastError()));
                }
            }
        }
    }
}

// Trailing stop for open positions.
void DoTrail()
{
    double Ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double Bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    int total = PositionsTotal();
    for (int cnt = 0; cnt < total; cnt++)
    {
        if (PositionGetSymbol(cnt) != Symbol()) continue;
        if (PositionGetInteger(POSITION_MAGIC) != Magic) continue;

        if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) && (Bid - PositionGetDouble(POSITION_PRICE_OPEN) > TrailingStop * Poin) && (PositionGetDouble(POSITION_SL) < NormalizeDouble(Bid - TrailingStop * Poin, _Digits)))
        {
            double NewSL = NormalizeDouble(Bid - TrailingStop * Poin, _Digits);
            if (Bid - NewSL > SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * _Point)
            {
                Trade.PositionModify(_Symbol, NewSL, PositionGetDouble(POSITION_TP));
            }
        }
        else if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) && (PositionGetDouble(POSITION_PRICE_OPEN) - Ask > TrailingStop * Poin) && ((PositionGetDouble(POSITION_SL) > NormalizeDouble(Ask + TrailingStop * Poin, _Digits)) || (PositionGetDouble(POSITION_SL) == 0)))
        {
            double NewSL = NormalizeDouble(Ask + TrailingStop * Poin, _Digits);
            if (NewSL - Ask > SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * _Point)
            {
                Trade.PositionModify(_Symbol, NewSL, PositionInfo.TakeProfit());
            }
        }
    }
}

void DeleteBuyStop()
{
    for (int i = 0; i < OrdersTotal(); i++)
    {
        ulong ticket = OrderGetTicket(i);
        if (OrderSelect(ticket))
        {
            if ((OrderGetString(ORDER_SYMBOL) == _Symbol) && (OrderGetInteger(ORDER_MAGIC) == Magic) && (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP))
            {
                if (!Trade.OrderDelete(ticket))
                {
                    Write("Error deleting Buy Stop: " + ErrorDescription(GetLastError()));
                }
                else Write("Buy Stop order deleted.");
                return;
            }
        }
    }
}

void DeleteSellStop()
{
    for (int i = 0; i < OrdersTotal(); i++)
    {
        ulong ticket = OrderGetTicket(i);
        if (OrderSelect(ticket))
        {
            if ((OrderGetString(ORDER_SYMBOL) == _Symbol) && (OrderGetInteger(ORDER_MAGIC) == Magic) && (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP))
            {
                if (!Trade.OrderDelete(ticket))
                {
                    Write("Error deleting Sell Stop: " + ErrorDescription(GetLastError()));
                }
                else Write("Sell Stop order deleted.");
                return;
            }
        }
    }
}

// Update pending stop orders according to new price levels.
void DoModify()
{
    for (int i = 0; i < OrdersTotal(); i++)
    {
        ulong ticket = OrderGetTicket(i);
        if (!OrderSelect(ticket))
        {
            Write(__FUNCTION__ + " | Error selecting an order: " + ErrorDescription(GetLastError()));
            continue;
        }
        if ((OrderGetString(ORDER_SYMBOL) != Symbol()) || (OrderGetInteger(ORDER_MAGIC) != Magic)) continue;

        if (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP)
        {
            if (OrderGetDouble(ORDER_PRICE_OPEN) != buy_stop_entry)
            {
                if (!Trade.OrderModify(ticket, buy_stop_entry, buy_stop_loss, buy_take_profit, 0, 0))
                {
                    Write(__FUNCTION__ + " | Error modifying Buy Stop: " + ErrorDescription(GetLastError()));
                }
                else Write("Buy Stop OrderModify executed: " + DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN), _Digits) + " -> " + DoubleToString(buy_stop_entry, _Digits));
            }
        }
        if (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP)
        {
            if (OrderGetDouble(ORDER_PRICE_OPEN) != sell_stop_entry)
            {
                if (!Trade.OrderModify(ticket, sell_stop_entry, sell_stop_entry, sell_take_profit, 0, 0))
                {
                    Write(__FUNCTION__ + " | Error modifying Sell Stop: " + ErrorDescription(GetLastError()));
                }
                else Write("Sell Stop OrderModify executed: " + DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN), _Digits) + " -> " + DoubleToString(sell_stop_entry, _Digits));
            }
        }
    }
}

// Prints a string and writes it to a log file too.
void Write(string str)
{
    Print(str);

    if (filename == "") return;

    int handle = FileOpen(filename, FILE_READ | FILE_WRITE | FILE_TXT);
    if (handle == INVALID_HANDLE)
    {
        Print("Error opening file ", filename, ": ", ErrorDescription(GetLastError()));
        return;
    }
    FileSeek(handle, 0, SEEK_END);
    FileWrite(handle, str + " Time " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
    FileClose(handle);
}

void OnTick()
{
    if (BEPips > 0) DoBE(BEPips);
    if (TrailingStop > 0) DoTrail();

    int OrdersCondition = CheckOrdersCondition();

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(NULL, PERIOD_M1, 0, CTCBN + 1, rates);
    if (copied != CTCBN + 1) Print("Error copying price data: ", ErrorDescription(GetLastError()));

    double Ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double Bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    double recent_high = rates[0].high;
    double recent_low = rates[0].low;
    for (int i = 1; i <= CTCBN; i++)
    {
        if (rates[i].high > recent_high) recent_high = rates[i].high;
        if (rates[i].low < recent_low) recent_low = rates[i].low;
    }
    double spread = Ask - Bid;
    buy_stop_entry = NormalizeDouble(recent_high + spread + 10 * Poin, _Digits);
    sell_stop_entry = NormalizeDouble(recent_low - 10 * Poin, _Digits);
    buy_stop_loss = NormalizeDouble(recent_high + spread, _Digits);
    sell_stop_loss = NormalizeDouble(recent_low, _Digits);
    buy_take_profit = NormalizeDouble(buy_stop_entry + TP * Poin, _Digits);
    sell_take_profit= NormalizeDouble(sell_stop_entry - TP * Poin, _Digits);

    int sectonews = (int)(NewsDateTime - TimeCurrent());
    Comment("\nAmazing Expert Advisor",
            "\nHigh @ ", recent_high, " Buy Order @ ", buy_stop_entry, " Stop-loss @ ", buy_stop_loss, " Take-profit @ ", buy_take_profit, 
            "\nLow @ ", recent_low, " Sell Order @ ", sell_stop_entry, " Stop-loss @ ", sell_stop_loss, " Take-profit @ ", sell_take_profit, 
            "\nNews time: ", TimeToString(NewsDateTime), 
            "\nCurrent time: ", TimeToString(TimeCurrent()), 
            "\nSeconds left to news: ", IntegerToString(sectonews), 
            "\nCTCBN: ", CTCBN, " SecBPO: ", SecBPO, " SecBMO: ", SecBMO, " STWAN: ", STWAN, " OCO: ", OCO, " BEPips: ", BEPips, 
            "\nMoney management: ", MM, " RiskPercent: ", RiskPercent, " Lots: ", LotsOptimized());

    // Before the news, but after the time when orders have to be placed.
    if ((TimeCurrent() < NewsDateTime) && (TimeCurrent() >= NewsDateTime - SecBPO))
    {
        if (OrdersCondition == 0) // No orders.
        {
            Write("Opening Buy Stop and Sell Stop. OrdersCondition = " + IntegerToString(OrdersCondition) + " Timestamp = " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + ".");
            OpenBuyStop();
            OpenSellStop();
        }
        else if (OrdersCondition == 10)
        {
            Write("Opening Sell Stop. OrdersCondition = " + IntegerToString(OrdersCondition) + " Timestamp = " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + ".");
            OpenSellStop();
        }
        else if (OrdersCondition == 1)
        {
            Write("Opening Buy Stop. OrdersCondition = " + IntegerToString(OrdersCondition) + " Timestamp = " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + ".");
            OpenBuyStop();
        }
    }

    // Still have time to modify the orders.
    if ((TimeCurrent() < NewsDateTime) && (TimeCurrent() >= NewsDateTime - SecBPO) && (TimeCurrent() < NewsDateTime - SecBMO))
    {
        Write("Modifying orders. OrdersCondition = " + IntegerToString(OrdersCondition) + " Timestamp = " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + ".");
        DoModify();
    }

    // News announcement already happened, but it is too early to delete all untriggered orders, yet the EA has to delete the untriggered one due to OCO if the opposite was hit.
    if ((TimeCurrent() > NewsDateTime) && (TimeCurrent() < NewsDateTime + STWAN) && (OCO))
    {
        if (OrdersCondition == 1001)
        {
            Write("Deleting Sell Stop because Buy Stop was hit. OrdersCondition = " + IntegerToString(OrdersCondition) + " Timestamp = " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + ".");
            DeleteSellStop();
        }
        else if (OrdersCondition == 110)
        {
            Write("Deleting Buy Stop because Sell Stop was hit. OrdersCondition=" + IntegerToString(OrdersCondition) + " Timestamp=" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + ".");
            DeleteBuyStop();
        }
    }

    // News has passed and it is time to delete untriggered orders.
    if ((TimeCurrent() > NewsDateTime) && (TimeCurrent() > NewsDateTime + STWAN))
    {
        if (OrdersCondition == 11)
        {
            Write("Deleting Buy Stop and Sell Stop because time expired. OrdersCondition = " + IntegerToString(OrdersCondition) + " Timestamp=" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + ".");
            DeleteBuyStop();
            DeleteSellStop();
        }

        if ((OrdersCondition == 10) || (OrdersCondition == 110))
        {
            Write("Deleting BuyStop Because expired, OrdersCondition=" + IntegerToString(OrdersCondition) + " Timestamp = " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + ".");
            DeleteBuyStop();
        }

        if ((OrdersCondition == 1) || (OrdersCondition == 1001))
        {
            Write("Deleting SellStop Because expired, OrdersCondition=" + IntegerToString(OrdersCondition) + " Timestamp = " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + ".");
            DeleteSellStop();
        }
    }
}

//+------------------------------------------------------------------+
//| Counts decimal places.                                           |
//+------------------------------------------------------------------+
int CountDecimalPlaces(double number)
{
    // 100 as maximum length of number.
    for (int i = 0; i < 100; i++)
    {
        double pwr = MathPow(10, i);
        if (MathRound(number * pwr) / pwr == number) return i;
    }
    return -1;
}
//+------------------------------------------------------------------+