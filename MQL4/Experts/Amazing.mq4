//+------------------------------------------------------------------+
//|                                                          Amazing |
//|                                  Copyright © 2023, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//|                                 Based on the EA by FiFtHeLeMeNt. |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2023, EarnForex"
#property link      "https://www.earnforex.com/metatrader-expert-advisors/Amazing/"
#property version   "1.04"
#property strict

#property description "Amazing - EA that helps to trade on news."
#property description "Set the NewsDateTime input parameter to the actual date and time of the news."
#property description "EA will set up the pending orders (buy and sell) to be triggered by the news."
#property description "It will use a profit target, breakeven, and trailing stop to manage it."

#include <stdlib.mqh>

input group "Main"
input datetime NewsDateTime = __DATE__; // NewsDateTime: Date and time of the news release.
input int EntryDistance = 100; // EntryDistance: Entry distance from recent high/low in points.
input int StopLoss = 200; // StopLoss: Stop-loss in points.
input int TakeProfit = 200; // TakeProfit: Take-profit in points.
input int CTCBN = 0; // CTCBN: Number of candles to check before news for High & Low.
input int SecBPO = 300; // SecBPO: Seconds before news to place pending orders.
input int SecBMO = 0; // SecBMO: Seconds before news when to stop modifying orders.
input int STWAN = 150; // STWAN: Seconds to wait after news to delete pending orders.
input bool OCO = true; // OCO: EA will cancel the other pending order if one is hit.
input int BEPoints = 0; // BEPoints: Points of profit when EA will move SL to breakeven + 1.
input int TrailingStop = 0; // Trailing Stop in points
input group "ATR"
input bool UseATR = false; // Use ATR-based stop-loss and take-profit levels.
input int ATR_Period = 14; // ATR Period.
input double ATR_Multiplier_SL = 5; // ATR multiplier for SL.
input double ATR_Multiplier_TP = 5; // ATR multiplier for TP.
input group "Money management"
input double Lots = 0.01;
input bool MM  = true; // Money Management, if true - position sizing based on stop-loss.
input double Risk = 1; // Risk - Risk tolerance in percentage points.
input double FixedBalance = 0; // FixedBalance: If > 0, trade size calc. uses it as balance.
input double MoneyRisk = 0; // MoneyRisk: Risk tolerance in account currency.
input bool UseMoneyInsteadOfPercentage = false; // Use money risk instead of percentage.
input bool UseEquityInsteadOfBalance = false; // Use equity instead of balance.
input group "Miscellaneous"
input string TradeLog = "Am_Log_"; // TradeLog: Log file prefix.
input string Commentary = "Amazing"; // Commentary: trade description.

// Global variables:
double buy_stop_entry, sell_stop_entry, buy_stop_loss, sell_stop_loss, buy_take_profit, sell_take_profit;
int Magic;
string filename;

double SL, TP;
double RiskMoney;

// For tick value adjustment:
string ProfitCurrency = "", account_currency = "", BaseCurrency = "", ReferenceSymbol = NULL, AdditionalReferenceSymbol = NULL;
bool ReferenceSymbolMode, AdditionalReferenceSymbolMode;
int ProfitCalcMode;

void OnInit()
{
    Magic = (int)NewsDateTime; // Dynamically generated Magic number to allow multiple instances for different news announcements.
    
    double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    Print("Minimum lot: ", DoubleToString(min_lot, 2), ", lot step: ", DoubleToString(lot_step, 2), ".");
    if ((Lots < min_lot) && (!MM)) Alert("Lots should be not less than: ", DoubleToString(min_lot, 2), ".");

    // If UseATR = false, these values will be used. Otherwise, ATR values will be calculated later.
    SL = StopLoss;
    TP = TakeProfit;

    if (StringLen(Commentary) > 0) filename = TradeLog + Symbol() + "-" + IntegerToString(Month()) + "-" + IntegerToString(Day()) + ".txt";
    else filename = ""; // Turning logging off.
}

void OnDeinit(const int reason)
{
    Comment("");
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
        int ticket = OrderSend(Symbol(), OP_BUYSTOP, LotsOptimized(OP_BUY, buy_stop_entry), buy_stop_entry, 0, buy_stop_loss, buy_take_profit, Commentary, Magic);
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
        int ticket = OrderSend(Symbol(), OP_SELLSTOP, LotsOptimized(OP_SELL, sell_stop_entry), sell_stop_entry, 0, sell_stop_loss, sell_take_profit, Commentary, Magic);
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
void DoBE(int byPoints)
{
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            Write(__FUNCTION__ + " | Error selecting an order: " + ErrorDescription(GetLastError()));
            continue;
        }
        if ((OrderSymbol() != Symbol()) || (OrderMagicNumber() != Magic)) continue;

        if ((OrderType() == OP_BUY) && (NormalizeDouble(Bid - OrderOpenPrice(), _Digits) > NormalizeDouble(byPoints * _Point, _Digits)) && (OrderStopLoss() < OrderOpenPrice()))
        {
            Write("Moving stop-loss of Buy order to breakeven + 1 point.");
            if (!OrderModify(OrderTicket(), OrderOpenPrice(), OrderOpenPrice() + _Point, OrderTakeProfit(), OrderExpiration()))
            {
                Write(__FUNCTION__ + " | Error modifying Buy: " + ErrorDescription(GetLastError()));
            }
        }
        else if ((OrderType() == OP_SELL) && (NormalizeDouble(OrderOpenPrice() - Ask, _Digits) > NormalizeDouble(byPoints * _Point, _Digits)) && (OrderStopLoss() > OrderOpenPrice()))
        {
            Write("Moving stop-loss of Sell order to breakeven - 1 point.");
            if (!OrderModify(OrderTicket(), OrderOpenPrice(), OrderOpenPrice() - _Point, OrderTakeProfit(), OrderExpiration()))
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
            if (Bid - OrderOpenPrice() > _Point * TrailingStop)
            {
                if (OrderStopLoss() < NormalizeDouble(Bid - _Point * TrailingStop, _Digits))
                {
                    if (!OrderModify(OrderTicket(), OrderOpenPrice(), Bid - _Point * TrailingStop, OrderTakeProfit(), OrderExpiration()))
                    {
                        Write(__FUNCTION__ + " | Error modifying Buy: " + ErrorDescription(GetLastError()));
                    }
                }
            }
        }
        else if (OrderType() == OP_SELL)
        {
            if (OrderOpenPrice() - Ask > _Point * TrailingStop)
            {
                if ((OrderStopLoss() > NormalizeDouble(Ask + _Point * TrailingStop, _Digits)) || (OrderStopLoss() == 0))
                {
                    if (!OrderModify(OrderTicket(), OrderOpenPrice(), Ask + _Point * TrailingStop, OrderTakeProfit(), OrderExpiration()))
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
    if (BEPoints > 0) DoBE(BEPoints);
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
    buy_stop_entry = NormalizeDouble(recent_high + spread + EntryDistance * _Point, _Digits);
    sell_stop_entry = NormalizeDouble(recent_low - EntryDistance * _Point, _Digits);

    if (UseATR)
    {
        // Getting the ATR values
        double ATR = iATR(NULL, 0, ATR_Period, 0);
        SL = ATR * ATR_Multiplier_SL;
        if (SL <= (SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) + SymbolInfoInteger(Symbol(), SYMBOL_SPREAD)) * Point) SL = (SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) + SymbolInfoInteger(Symbol(), SYMBOL_SPREAD)) * Point;
        TP = ATR * ATR_Multiplier_TP;
        if (TP <= (SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) + SymbolInfoInteger(Symbol(), SYMBOL_SPREAD)) * Point) TP = (SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) + SymbolInfoInteger(Symbol(), SYMBOL_SPREAD)) * Point;
        SL /= Point;
        TP /= Point;
    }

    buy_stop_loss = NormalizeDouble(buy_stop_entry - SL * _Point, _Digits);
    sell_stop_loss = NormalizeDouble(sell_stop_entry + SL * _Point, _Digits);
    buy_take_profit = NormalizeDouble(buy_stop_entry + TP * _Point, _Digits);
    sell_take_profit= NormalizeDouble(sell_stop_entry - TP * _Point, _Digits);

    int sectonews = (int)(NewsDateTime - TimeCurrent());
    Comment("\nAmazing Expert Advisor",
            "\nHigh @ ", recent_high, " Buy Order @ ", buy_stop_entry, " Stop-loss @ ", buy_stop_loss, " Take-profit @ ", buy_take_profit, 
            "\nLow @ ", recent_low, " Sell Order @ ", sell_stop_entry, " Stop-loss @ ", sell_stop_loss, " Take-profit @ ", sell_take_profit, 
            "\nNews time: ", TimeToString(NewsDateTime), 
            "\nCurrent time: ", TimeToString(TimeCurrent()), 
            "\nSeconds left to news: ", IntegerToString(sectonews), 
            "\nCTCBN: ", CTCBN, " SecBPO: ", SecBPO, " SecBMO: ", SecBMO, " STWAN: ", STWAN, " OCO: ", OCO, " BEPips: ", BEPoints, 
            "\nMoney management: ", MM, " Risk: ", DoubleToString(RiskMoney, 2), " ", AccountCurrency(), " Lots (B/S): ", DoubleToString(LotsOptimized(OP_BUY, buy_stop_entry), 2), "/", DoubleToString(LotsOptimized(OP_SELL, sell_stop_entry), 2));

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
//| Calculate position size depending on money management parameters.|
//+------------------------------------------------------------------+
double LotsOptimized(int dir, double entry)
{
    if (!MM) return Lots;

    double Size, PositionSize = 0, UnitCost;
    ProfitCurrency = SymbolInfoString(Symbol(), SYMBOL_CURRENCY_PROFIT);
    BaseCurrency = SymbolInfoString(Symbol(), SYMBOL_CURRENCY_BASE);
    ProfitCalcMode = (int)MarketInfo(Symbol(), MODE_PROFITCALCMODE);
    account_currency = AccountCurrency();
    // A rough patch for cases when account currency is set as RUR instead of RUB.
    if (account_currency == "RUR") account_currency = "RUB";
    if (ProfitCurrency == "RUR") ProfitCurrency = "RUB";
    if (BaseCurrency == "RUR") BaseCurrency = "RUB";
    double LotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
    int LotStep_digits = CountDecimalPlaces(LotStep);

    if (AccountCurrency() == "") return 0;

    if (FixedBalance > 0)
    {
        Size = FixedBalance;
    }
    else if (UseEquityInsteadOfBalance)
    {
        Size = AccountEquity();
    }
    else
    {
        Size = AccountBalance();
    }

    if (!UseMoneyInsteadOfPercentage) RiskMoney = Size * Risk / 100;
    else RiskMoney = MoneyRisk;

    // If Symbol is CFD.
    if (ProfitCalcMode == 1)
        UnitCost = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE) * SymbolInfoDouble(Symbol(), SYMBOL_TRADE_CONTRACT_SIZE); // Apparently, it is more accurate than taking TICKVALUE directly in some cases.
    else UnitCost = MarketInfo(Symbol(), MODE_TICKVALUE); // Futures or Forex.

    if (ProfitCalcMode != 0)  // Non-Forex might need to be adjusted.
    {
        // If profit currency is different from account currency.
        if (ProfitCurrency != account_currency)
        {
            double CCC = CalculateAdjustment(); // Valid only for loss calculation.
            // Adjust the unit cost.
            UnitCost *= CCC;
        }
    }

    // If account currency == pair's base currency, adjust UnitCost to future rate (SL). Works only for Forex pairs.
    if ((account_currency == BaseCurrency) && (ProfitCalcMode == 0))
    {
        double current_rate = 1, future_rate = 1;
        RefreshRates();
        if (dir == OP_BUY)
        {
            if (entry == 0) current_rate = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            else current_rate = entry;
            future_rate = current_rate - SL * _Point;
        }
        else if (dir == OP_SELL)
        {
            if (entry == 0) current_rate = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            else current_rate = entry;
            future_rate = current_rate + SL * _Point;
        }
        if (future_rate == 0) future_rate = _Point; // Zero divide prevention.
        UnitCost *= (current_rate / future_rate);
    }

    double TickSize = MarketInfo(Symbol(), MODE_TICKSIZE);

    if ((SL != 0) && (UnitCost != 0) && (TickSize != 0)) PositionSize = NormalizeDouble(RiskMoney / (SL * _Point * UnitCost / TickSize), LotStep_digits);

    if (PositionSize < MarketInfo(Symbol(), MODE_MINLOT))
    {
        Print("Calculated position size (" + DoubleToString(PositionSize, 2) + ") is less than minimum position size (" + DoubleToString(MarketInfo(Symbol(), MODE_MINLOT), 2) + "). Setting position size to minimum.");
        PositionSize = MarketInfo(Symbol(), MODE_MINLOT);
    }
    else if (PositionSize > MarketInfo(Symbol(), MODE_MAXLOT))
    {
        Print("Calculated position size (" + DoubleToString(PositionSize, 2) + ") is greater than maximum position size (" + DoubleToString(MarketInfo(Symbol(), MODE_MAXLOT), 2) + "). Setting position size to maximum.");
        PositionSize = MarketInfo(Symbol(), MODE_MAXLOT);
    }

    double steps = PositionSize / LotStep;
    if (MathAbs(MathRound(steps) - steps) < 0.00000001) steps = MathRound(steps);
    if (steps - MathFloor(steps) > 0.5)
    {
Print(steps, " ", MathFloor(steps));        
        Print("Calculated position size (" + DoubleToString(PositionSize, 2) + ") uses uneven step size. Allowed step size = " + DoubleToString(MarketInfo(Symbol(), MODE_LOTSTEP), 2) + ". Setting position size to " + DoubleToString(MathFloor(steps) * LotStep, 2) + ".");
        PositionSize = MathFloor(steps) * LotStep;
    }

    return PositionSize;
}

//+-----------------------------------------------------------------------------------+
//| Calculates necessary adjustments for cases when ProfitCurrency != AccountCurrency.|
//+-----------------------------------------------------------------------------------+
#define FOREX_SYMBOLS_ONLY 0
#define NONFOREX_SYMBOLS_ONLY 1
double CalculateAdjustment()
{
    double add_coefficient = 1; // Might be necessary for correction coefficient calculation if two pairs are used for profit currency to account currency conversion. This is handled differently in MT5 version.
    if (ReferenceSymbol == NULL)
    {
        ReferenceSymbol = GetSymbolByCurrencies(ProfitCurrency, account_currency, FOREX_SYMBOLS_ONLY);
        if (ReferenceSymbol == NULL) ReferenceSymbol = GetSymbolByCurrencies(ProfitCurrency, account_currency, NONFOREX_SYMBOLS_ONLY);
        ReferenceSymbolMode = true;
        // Failed.
        if (ReferenceSymbol == NULL)
        {
            // Reversing currencies.
            ReferenceSymbol = GetSymbolByCurrencies(account_currency, ProfitCurrency, FOREX_SYMBOLS_ONLY);
            if (ReferenceSymbol == NULL) ReferenceSymbol = GetSymbolByCurrencies(account_currency, ProfitCurrency, NONFOREX_SYMBOLS_ONLY);
            ReferenceSymbolMode = false;
        }
        if (ReferenceSymbol == NULL)
        {
            // The condition checks whether we are caclulating conversion coefficient for the chart's symbol or for some other.
            // The error output is OK for the current symbol only because it won't be repeated ad infinitum.
            // It should be avoided for non-chart symbols because it will just flood the log.
            Print("Couldn't detect proper currency pair for adjustment calculation. Profit currency: ", ProfitCurrency, ". Account currency: ", account_currency, ". Trying to find a possible two-symbol combination.");
            if ((FindDoubleReferenceSymbol("USD"))  // USD should work in 99.9% of cases.
             || (FindDoubleReferenceSymbol("EUR"))  // For very rare cases.
             || (FindDoubleReferenceSymbol("GBP"))  // For extremely rare cases.
             || (FindDoubleReferenceSymbol("JPY"))) // For extremely rare cases.
            {
                Print("Converting via ", ReferenceSymbol, " and ", AdditionalReferenceSymbol, ".");
            }
            else
            {
                Print("Adjustment calculation critical failure. Failed both simple and two-pair conversion methods.");
                return 1;
            }
        }
    }
    if (AdditionalReferenceSymbol != NULL) // If two reference pairs are used.
    {
        // Calculate just the additional symbol's coefficient and then use it in final return's multiplication.
        MqlTick tick;
        SymbolInfoTick(AdditionalReferenceSymbol, tick);
        add_coefficient = GetCurrencyCorrectionCoefficient(tick, AdditionalReferenceSymbolMode);
    }
    MqlTick tick;
    SymbolInfoTick(ReferenceSymbol, tick);
    return GetCurrencyCorrectionCoefficient(tick, ReferenceSymbolMode) * add_coefficient;
}

//+---------------------------------------------------------------------------+
//| Returns a currency pair with specified base currency and profit currency. |
//+---------------------------------------------------------------------------+
string GetSymbolByCurrencies(const string base_currency, const string profit_currency, const uint symbol_type)
{
    // Cycle through all symbols.
    for (int s = 0; s < SymbolsTotal(false); s++)
    {
        // Get symbol name by number.
        string symbolname = SymbolName(s, false);
        string b_cur;

        // Normal case - Forex pairs:
        if (MarketInfo(symbolname, MODE_PROFITCALCMODE) == 0)
        {
            if (symbol_type == NONFOREX_SYMBOLS_ONLY) continue; // Avoid checking symbols of a wrong type.
            // Get its base currency.
            b_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_BASE);
        }
        else // Weird case for brokers that set conversion pairs as CFDs.
        {
            if (symbol_type == FOREX_SYMBOLS_ONLY) continue; // Avoid checking symbols of a wrong type.
            // Get its base currency as the initial three letters - prone to huge errors!
            b_cur = StringSubstr(symbolname, 0, 3);
        }

        // Get its profit currency.
        string p_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_PROFIT);

        // If the currency pair matches both currencies, select it in Market Watch and return its name.
        if ((b_cur == base_currency) && (p_cur == profit_currency))
        {
            // Select if necessary.
            if (!(bool)SymbolInfoInteger(symbolname, SYMBOL_SELECT)) SymbolSelect(symbolname, true);

            return symbolname;
        }
    }
    return NULL;
}

//+----------------------------------------------------------------------------+
//| Finds reference symbols using 2-pair method.                               |
//| Results are returned via reference parameters.                             |
//| Returns true if found the pairs, false otherwise.                          |
//+----------------------------------------------------------------------------+
bool FindDoubleReferenceSymbol(const string cross_currency)
{
    // A hypothetical example for better understanding:
    // The trader buys CAD/CHF.
    // account_currency is known = SEK.
    // cross_currency = USD.
    // profit_currency = CHF.
    // I.e., we have to buy dollars with francs (using the Ask price) and then sell those for SEKs (using the Bid price).

    ReferenceSymbol = GetSymbolByCurrencies(cross_currency, account_currency, FOREX_SYMBOLS_ONLY); 
    if (ReferenceSymbol == NULL) ReferenceSymbol = GetSymbolByCurrencies(cross_currency, account_currency, NONFOREX_SYMBOLS_ONLY);
    ReferenceSymbolMode = true; // If found, we've got USD/SEK.

    // Failed.
    if (ReferenceSymbol == NULL)
    {
        // Reversing currencies.
        ReferenceSymbol = GetSymbolByCurrencies(account_currency, cross_currency, FOREX_SYMBOLS_ONLY);
        if (ReferenceSymbol == NULL) ReferenceSymbol = GetSymbolByCurrencies(account_currency, cross_currency, NONFOREX_SYMBOLS_ONLY);
        ReferenceSymbolMode = false; // If found, we've got SEK/USD.
    }
    if (ReferenceSymbol == NULL)
    {
        Print("Error. Couldn't detect proper currency pair for 2-pair adjustment calculation. Cross currency: ", cross_currency, ". Account currency: ", account_currency, ".");
        return false;
    }

    AdditionalReferenceSymbol = GetSymbolByCurrencies(cross_currency, ProfitCurrency, FOREX_SYMBOLS_ONLY); 
    if (AdditionalReferenceSymbol == NULL) AdditionalReferenceSymbol = GetSymbolByCurrencies(cross_currency, ProfitCurrency, NONFOREX_SYMBOLS_ONLY);
    AdditionalReferenceSymbolMode = false; // If found, we've got USD/CHF. Notice that mode is swapped for cross/profit compared to cross/acc, because it is used in the opposite way.

    // Failed.
    if (AdditionalReferenceSymbol == NULL)
    {
        // Reversing currencies.
        AdditionalReferenceSymbol = GetSymbolByCurrencies(ProfitCurrency, cross_currency, FOREX_SYMBOLS_ONLY);
        if (AdditionalReferenceSymbol == NULL) AdditionalReferenceSymbol = GetSymbolByCurrencies(ProfitCurrency, cross_currency, NONFOREX_SYMBOLS_ONLY);
        AdditionalReferenceSymbolMode = true; // If found, we've got CHF/USD. Notice that mode is swapped for profit/cross compared to acc/cross, because it is used in the opposite way.
    }
    if (AdditionalReferenceSymbol == NULL)
    {
        Print("Error. Couldn't detect proper currency pair for 2-pair adjustment calculation. Cross currency: ", cross_currency, ". Chart's pair currency: ", ProfitCurrency, ".");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Get profit correction coefficient based on current prices.       |
//| Valid for loss calculation only.                                 |
//+------------------------------------------------------------------+
double GetCurrencyCorrectionCoefficient(MqlTick &tick, const bool ref_symbol_mode)
{
    if ((tick.ask == 0) || (tick.bid == 0)) return -1; // Data is not yet ready.
    // Reverse quote.
    if (ref_symbol_mode)
    {
        // Using Buy price for reverse quote.
        return tick.ask;
    }
    // Direct quote.
    else
    {
        // Using Sell price for direct quote.
        return (1 / tick.bid);
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