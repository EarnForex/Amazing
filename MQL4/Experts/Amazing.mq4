//+------------------------------------------------------------------+
//|                                                          Amazing |
//|                             Copyright © 2008-2022, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//|                                 Based on the EA by FiFtHeLeMeNt. |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2008-2022, EarnForex"
#property link      "https://www.earnforex.com/metatrader-expert-advisors/Amazing/"
#property version   "1.03"
#property strict

#property description "Amazing - EA that helps to trade on news."
#property description "Set the NewsDateTime input parameter to the actual date and time of the news."
#property description "EA will set up the pending orders (buy and sell) to be triggered by the news."
#property description "It will use a profit target, breakeven, and trailing stop to manage it."

#include <stdlib.mqh>

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

void OnInit()
{
    Magic = (int)NewsDateTime; // Dynamically generated Magic number to allow multiple instances for different news announcements.

    // Checking for unconventional Point digits number.
    if (Point == 0.00001) Poin = 0.0001; // 5 digits.
    else if (Point == 0.001) Poin = 0.01; // 3 digits.
    else Poin = Point; // Normal.

    if (StringLen(Commentary) > 0) filename = TradeLog + Symbol() + "-" + IntegerToString(Month()) + "-" + IntegerToString(Day()) + ".txt";
    else filename = ""; // Turning logging off.
}

void OnDeinit(const int reason)
{
    Comment("");
}

//+------------------------------------------------------------------+
//| Returns lots number based on simple money management.            |
//+------------------------------------------------------------------+
double LotsOptimized()
{
    double lot = Lots;
    if (MM)
    {
        double LotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
        int LotStep_digits = CountDecimalPlaces(LotStep);
        lot = NormalizeDouble(MathFloor(AccountFreeMargin() * RiskPercent / 100) / 100, LotStep_digits);
    }

    // lot at this point is the number of standard lots.
    return lot;
}

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
    
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            Write(__FUNCTION__ + " | Error selecting an order: " + ErrorDescription(GetLastError()));
            continue;
        }
        if ((OrderSymbol() != Symbol()) || (OrderMagicNumber() != Magic)) continue;
        
        if (OrderType() == OP_BUY)
        {
            result = result + 1000;
        }
        else if (OrderType() == OP_SELL)
        {
            result = result + 100;
        }
        else if (OrderType() == OP_BUYSTOP)
        {
            result = result + 10;
        }
        else if (OrderType() == OP_SELLSTOP)
        {
            result = result + 1;
        }
    }
    
    return result; // 0 means there are no trades.
}

void OpenBuyStop()
{
    for (int tries = 0; tries < 10; tries++)
    {
        int ticket = OrderSend(Symbol(), OP_BUYSTOP, LotsOptimized(), buy_stop_entry, Slippage, buy_stop_loss, buy_take_profit, Commentary, Magic);
        if (ticket < 0)
        {
            Write("Error in OrderSend: " + ErrorDescription(GetLastError()) + " Buy Stop @ " + DoubleToString(buy_stop_entry, _Digits) + " SL @ " + DoubleToString(buy_stop_loss, _Digits) + " TP @" + DoubleToString(buy_take_profit, _Digits));
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
        int ticket = OrderSend(Symbol(), OP_SELLSTOP, LotsOptimized(), sell_stop_entry, Slippage, sell_stop_loss, sell_take_profit, Commentary, Magic);
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
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            Write(__FUNCTION__ + " | Error selecting an order: " + ErrorDescription(GetLastError()));
            continue;
        }
        if ((OrderSymbol() != Symbol()) || (OrderMagicNumber() != Magic)) continue;

        if ((OrderType() == OP_BUY) && (NormalizeDouble(Bid - OrderOpenPrice(), _Digits) > NormalizeDouble(byPips * Poin, _Digits)) && (OrderStopLoss() < OrderOpenPrice()))
        {
            Write("Moving stop-loss of Buy order to breakeven + 1 pip.");
            if (!OrderModify(OrderTicket(), OrderOpenPrice(), OrderOpenPrice() + Poin, OrderTakeProfit(), OrderExpiration()))
            {
                Write(__FUNCTION__ + " | Error modifying Buy: " + ErrorDescription(GetLastError()));
            }
        }
        else if ((OrderType() == OP_SELL) && (NormalizeDouble(OrderOpenPrice() - Ask, _Digits) > NormalizeDouble(byPips * Poin, _Digits)) && (OrderStopLoss() > OrderOpenPrice()))
        {
            Write("Moving stop-loss of Sell order to breakeven - 1 pip.");
            if (!OrderModify(OrderTicket(), OrderOpenPrice(), OrderOpenPrice() -  Poin, OrderTakeProfit(), OrderExpiration()))
            {
                Write(__FUNCTION__ + " | Error modifying Sell: " + ErrorDescription(GetLastError()));
            }
        }
    }
}

// Trailing stop for open positions.
void DoTrail()
{
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            Write(__FUNCTION__ + " | Error selecting an order: " + ErrorDescription(GetLastError()));
            continue;
        }
        if ((OrderSymbol() != Symbol()) || (OrderMagicNumber() != Magic)) continue;

        if (OrderType() == OP_BUY)
        {
            if (Bid - OrderOpenPrice() > Poin * TrailingStop)
            {
                if (OrderStopLoss() < NormalizeDouble(Bid - Poin * TrailingStop, _Digits))
                {
                    if (!OrderModify(OrderTicket(), OrderOpenPrice(), Bid - Poin * TrailingStop, OrderTakeProfit(), OrderExpiration()))
                    {
                        Write(__FUNCTION__ + " | Error modifying Buy: " + ErrorDescription(GetLastError()));
                    }
                }
            }
        }
        else if (OrderType() == OP_SELL)
        {
            if (OrderOpenPrice() - Ask > Poin * TrailingStop)
            {
                if ((OrderStopLoss() > NormalizeDouble(Ask + Poin * TrailingStop, _Digits)) || (OrderStopLoss() == 0))
                {
                    if (!OrderModify(OrderTicket(), OrderOpenPrice(), Ask + Poin * TrailingStop, OrderTakeProfit(), OrderExpiration()))
                    {
                        Write(__FUNCTION__ + " | Error modifying Sell: " + ErrorDescription(GetLastError()));
                    }
                }
            }
        }
    }
}

void DeleteBuyStop()
{
    for (int i = 0; i < OrdersTotal(); i++) // The order of cycle doesn't matter as only one order will be deleted.
    {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            Write(__FUNCTION__ + " | Error selecting an order: " + ErrorDescription(GetLastError()));
            continue;
        }
        if ((OrderSymbol() != Symbol()) || (OrderMagicNumber() != Magic)) continue;
        
        if (OrderType() == OP_BUYSTOP)
        {
            if (!OrderDelete(OrderTicket()))
            {
                Write("Error deleting Buy Stop: " + ErrorDescription(GetLastError()));
            }
            else Write("Buy Stop order deleted.");
            return;
        }
    }
}

void DeleteSellStop()
{
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            Write(__FUNCTION__ + " | Error selecting an order: " + ErrorDescription(GetLastError()));
            continue;
        }
        if ((OrderSymbol() != Symbol()) || (OrderMagicNumber() != Magic)) continue;

        if (OrderType() == OP_SELLSTOP)
        {
            if (!OrderDelete(OrderTicket()))
            {
                Write("Error deleting Sell Stop: " + ErrorDescription(GetLastError()));
            }
            else Write("Sell Stop order deleted.");
            return;
        }
    }
}

// Update pending stop orders according to new price levels.
void DoModify()
{
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            Write(__FUNCTION__ + " | Error selecting an order: " + ErrorDescription(GetLastError()));
            continue;
        }
        if ((OrderSymbol() != Symbol()) || (OrderMagicNumber() != Magic)) continue;

        if (OrderType() == OP_BUYSTOP)
        {
            if (OrderOpenPrice() != buy_stop_entry)
            {
                if (!OrderModify(OrderTicket(), buy_stop_entry, buy_stop_loss, buy_take_profit, OrderExpiration()))
                {
                    Write(__FUNCTION__ + " | Error modifying Buy Stop: " + ErrorDescription(GetLastError()));
                }
                else Write("Buy Stop OrderModify executed: " + DoubleToString(OrderOpenPrice(), _Digits) + " -> " + DoubleToString(buy_stop_entry, _Digits));
            }
        }

        if (OrderType() == OP_SELLSTOP)
        {
            if (OrderOpenPrice() != sell_stop_entry)
            {
                if (!OrderModify(OrderTicket(), sell_stop_entry, sell_stop_loss, sell_take_profit, OrderExpiration()))
                {
                    Write(__FUNCTION__ + " | Error modifying Sell Stop: " + ErrorDescription(GetLastError()));
                }
                else Write("Sell Stop OrderModify executed: " + DoubleToString(OrderOpenPrice(), _Digits) + " -> " + DoubleToString(sell_stop_entry, _Digits));
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
    FileWrite(handle, str + " Time " + TimeToStr(CurTime(), TIME_DATE | TIME_SECONDS));
    FileClose(handle);
}

void OnTick()
{
    if (BEPips > 0) DoBE(BEPips);
    if (TrailingStop > 0) DoTrail();

    int OrdersCondition = CheckOrdersCondition();

    // Find recent High/Low for pre-news orders.
    double recent_high = iHigh(NULL, PERIOD_M1, 0);
    double recent_low = iLow(NULL, PERIOD_M1, 0);
    for (int i = 1; i <= CTCBN; i++)
    {
        if (iHigh(NULL, PERIOD_M1, i) > recent_high) recent_high = iHigh(NULL, PERIOD_M1, i);
        if (iLow(NULL, PERIOD_M1, i) < recent_low) recent_low = iLow(NULL, PERIOD_M1, i);
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