//+------------------------------------------------------------------+
//|                                                          Amazing |
//|                                  Copyright © 2023, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//|                                 Based on the EA by FiFtHeLeMeNt. |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2023, EarnForex"
#property link      "https://www.earnforex.com/metatrader-expert-advisors/Amazing/"
#property version   "1.04"

#property description "Amazing - EA that helps to trade on news."
#property description "Set the NewsDateTime input parameter to the actual date and time of the news."
#property description "EA will set up the pending orders (buy and sell) to be triggered by the news."
#property description "It will use a profit target, breakeven, and trailing stop to manage it."

#include <Trade/Trade.mqh>
#include <errordescription.mqh>

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
int lot_decimal_places;
int ATR_handle;
double RiskMoney;
string AccountCurrency = "";
string ProfitCurrency = "";
string BaseCurrency = "";
ENUM_SYMBOL_CALC_MODE CalcMode;
string ReferencePair = NULL;
bool ReferenceSymbolMode;

// Main trading objects:
CTrade *Trade;
CPositionInfo PositionInfo;
COrderInfo OrderInfo;

void OnInit()
{
    Magic = (int)NewsDateTime; // Dynamically generated Magic number to allow multiple instances for different news announcements.

    double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    lot_decimal_places = CountDecimalPlaces(lot_step);
    Print("Minimum lot: ", DoubleToString(min_lot, 2), ", lot step: ", DoubleToString(lot_step, lot_decimal_places), ".");
    if ((Lots < min_lot) && (!MM)) Alert("Lots should be not less than: ", DoubleToString(min_lot, lot_decimal_places), ".");

    if (StringLen(Commentary) > 0)
    {
        MqlDateTime dt;
        TimeCurrent(dt);
        filename = TradeLog + Symbol() + "-" + IntegerToString(dt.mon) + "-" + IntegerToString(dt.day) + ".txt";
    }
    
    if (UseATR) ATR_handle = iATR(NULL, 0, ATR_Period);

    // If UseATR = false, these values will be used. Otherwise, ATR values will be calculated later.
    SL = StopLoss;
    TP = TakeProfit;
    
    // Initialize the Trade class object
    Trade = new CTrade;
    Trade.SetExpertMagicNumber(Magic);
}

void OnDeinit(const int reason)
{
    Comment("");
    delete Trade;
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
        Trade.OrderOpen(_Symbol, ORDER_TYPE_BUY_STOP, LotsOptimized(ORDER_TYPE_BUY, buy_stop_entry), 0, buy_stop_entry, buy_stop_loss, buy_take_profit, 0, 0, Commentary);
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
        Trade.OrderOpen(_Symbol, ORDER_TYPE_SELL_STOP, LotsOptimized(ORDER_TYPE_SELL, sell_stop_entry), 0, sell_stop_entry, sell_stop_loss, sell_take_profit, 0, 0, Commentary);
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
void DoBE(int byPoints)
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
        
        if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) && (NormalizeDouble(Bid - PositionGetDouble(POSITION_PRICE_OPEN), _Digits) > NormalizeDouble(byPoints * _Point, _Digits)) && (PositionInfo.StopLoss() < PositionGetDouble(POSITION_PRICE_OPEN)))
        {
            double NewSL = NormalizeDouble(PositionInfo.PriceOpen() + _Point, _Digits);
            if (Bid - NewSL > SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * _Point)
            {
                Write("Moving stop-loss of Buy order to breakeven + 1 pip.");
                if (!Trade.PositionModify(_Symbol, NewSL, PositionGetDouble(POSITION_TP)))
                {
                    Write(__FUNCTION__ + " | Error modifying Buy: " + ErrorDescription(GetLastError()));
                }
            }
        }
        else if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) && (NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN) - Ask, _Digits) > NormalizeDouble(byPoints * _Point, _Digits)) && (PositionInfo.StopLoss() > PositionGetDouble(POSITION_PRICE_OPEN)))
        {
            double NewSL = NormalizeDouble(PositionInfo.PriceOpen() - _Point, _Digits);
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

        if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) && (Bid - PositionGetDouble(POSITION_PRICE_OPEN) > TrailingStop * _Point) && (PositionGetDouble(POSITION_SL) < NormalizeDouble(Bid - TrailingStop * _Point, _Digits)))
        {
            double NewSL = NormalizeDouble(Bid - TrailingStop * _Point, _Digits);
            if (Bid - NewSL > SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * _Point)
            {
                Trade.PositionModify(_Symbol, NewSL, PositionGetDouble(POSITION_TP));
            }
        }
        else if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) && (PositionGetDouble(POSITION_PRICE_OPEN) - Ask > TrailingStop * _Point) && ((PositionGetDouble(POSITION_SL) > NormalizeDouble(Ask + TrailingStop * _Point, _Digits)) || (PositionGetDouble(POSITION_SL) == 0)))
        {
            double NewSL = NormalizeDouble(Ask + TrailingStop * _Point, _Digits);
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
    AccountCurrency = AccountInfoString(ACCOUNT_CURRENCY);
    // A rough patch for cases when account currency is set as RUR instead of RUB.
    if (AccountCurrency == "RUR") AccountCurrency = "RUB";
    ProfitCurrency = SymbolInfoString(Symbol(), SYMBOL_CURRENCY_PROFIT);
    if (ProfitCurrency == "RUR") ProfitCurrency = "RUB";
    BaseCurrency = SymbolInfoString(Symbol(), SYMBOL_CURRENCY_BASE);
    if (BaseCurrency == "RUR") BaseCurrency = "RUB";
    
    if (BEPoints > 0) DoBE(BEPoints);
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
    buy_stop_entry = NormalizeDouble(recent_high + spread + EntryDistance * _Point, _Digits);
    sell_stop_entry = NormalizeDouble(recent_low - EntryDistance * _Point, _Digits);

    if (UseATR)
    {
        // Getting the ATR values.
        double ATR;
        double ATR_buffer[1];
        if (CopyBuffer(ATR_handle, 0, 1, 1, ATR_buffer) != 1)
        {
            Print("ATR data not ready!");
            return;
        }
        ATR = ATR_buffer[0];
        SL = ATR * ATR_Multiplier_SL;
        if (SL <= (SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) + SymbolInfoInteger(Symbol(), SYMBOL_SPREAD)) * _Point) SL = (SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) + SymbolInfoInteger(Symbol(), SYMBOL_SPREAD)) * _Point;
        TP = ATR * ATR_Multiplier_TP;
        if (TP <= (SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) + SymbolInfoInteger(Symbol(), SYMBOL_SPREAD)) * _Point) TP = (SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) + SymbolInfoInteger(Symbol(), SYMBOL_SPREAD)) * _Point;
        SL /= _Point;
        TP /= _Point;
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
            "\nMoney management: ", MM, " Risk: ", DoubleToString(RiskMoney, 2), " ", AccountCurrency, " Lots (B/S): ", DoubleToString(LotsOptimized(ORDER_TYPE_BUY, buy_stop_entry), lot_decimal_places), "/", DoubleToString(LotsOptimized(ORDER_TYPE_SELL, sell_stop_entry), lot_decimal_places));

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
//| Calculates unit cost based on profit calculation mode.           |
//+------------------------------------------------------------------+
double CalculateUnitCost()
{
    double UnitCost;
    // CFD.
    if (((CalcMode == SYMBOL_CALC_MODE_CFD) || (CalcMode == SYMBOL_CALC_MODE_CFDINDEX) || (CalcMode == SYMBOL_CALC_MODE_CFDLEVERAGE)))
        UnitCost = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE) * SymbolInfoDouble(Symbol(), SYMBOL_TRADE_CONTRACT_SIZE);
    // With Forex and futures instruments, tick value already equals 1 unit cost.
    else UnitCost = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE_LOSS);
    
    return UnitCost;
}

//+-----------------------------------------------------------------------------------+
//| Calculates necessary adjustments for cases when GivenCurrency != AccountCurrency. |
//+-----------------------------------------------------------------------------------+
double CalculateAdjustment()
{
    if (ReferencePair == NULL)
    {
        ReferencePair = GetSymbolByCurrencies(ProfitCurrency, AccountCurrency);
        ReferenceSymbolMode = true;
        // Failed.
        if (ReferencePair == NULL)
        {
            // Reversing currencies.
            ReferencePair = GetSymbolByCurrencies(AccountCurrency, ProfitCurrency);
            ReferenceSymbolMode = false;
        }
    }
    if (ReferencePair == NULL)
    {
        Print("Error! Cannot detect proper currency pair for adjustment calculation: ", ProfitCurrency, ", ", AccountCurrency, ".");
        ReferencePair = Symbol();
        return 1;
    }
    MqlTick tick;
    SymbolInfoTick(ReferencePair, tick);
    return GetCurrencyCorrectionCoefficient(tick);
}

//+---------------------------------------------------------------------------+
//| Returns a currency pair with specified base currency and profit currency. |
//+---------------------------------------------------------------------------+
string GetSymbolByCurrencies(string base_currency, string profit_currency)
{
    // Cycle through all symbols.
    for (int s = 0; s < SymbolsTotal(false); s++)
    {
        // Get symbol name by number.
        string symbolname = SymbolName(s, false);

        // Skip non-Forex pairs.
        if ((SymbolInfoInteger(symbolname, SYMBOL_TRADE_CALC_MODE) != SYMBOL_CALC_MODE_FOREX) && (SymbolInfoInteger(symbolname, SYMBOL_TRADE_CALC_MODE) != SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE)) continue;

        // Get its base currency.
        string b_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_BASE);
        if (b_cur == "RUR") b_cur = "RUB";

        // Get its profit currency.
        string p_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_PROFIT);
        if (p_cur == "RUR") p_cur = "RUB";

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

//+------------------------------------------------------------------+
//| Get correction coefficient based on currency, trade direction,   |
//| and current prices.                                              |
//+------------------------------------------------------------------+
double GetCurrencyCorrectionCoefficient(MqlTick &tick)
{
    if ((tick.ask == 0) || (tick.bid == 0)) return -1; // Data is not yet ready.
    // Reverse quote.
    if (ReferenceSymbolMode)
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
//| Calculate position size depending on money management parameters.|
//+------------------------------------------------------------------+
double LotsOptimized(ENUM_ORDER_TYPE dir, double entry)
{
    if (!MM) return (Lots);

    double PositionSize = 0, Size;

    if (AccountInfoString(ACCOUNT_CURRENCY) == "") return 0;

    if (FixedBalance > 0)
    {
        Size = FixedBalance;
    }
    else if (UseEquityInsteadOfBalance)
    {
        Size = AccountInfoDouble(ACCOUNT_EQUITY);
    }
    else
    {
        Size = AccountInfoDouble(ACCOUNT_BALANCE);
    }

    if (!UseMoneyInsteadOfPercentage) RiskMoney = Size * Risk / 100;
    else RiskMoney = MoneyRisk;

    double UnitCost = CalculateUnitCost();

    // If profit currency is different from account currency and Symbol is not a Forex pair or futures (CFD, and so on).
    if ((ProfitCurrency != AccountCurrency) && (CalcMode != SYMBOL_CALC_MODE_FOREX) && (CalcMode != SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE) && (CalcMode != SYMBOL_CALC_MODE_FUTURES) && (CalcMode != SYMBOL_CALC_MODE_EXCH_FUTURES) && (CalcMode != SYMBOL_CALC_MODE_EXCH_FUTURES_FORTS))
    {
        double CCC = CalculateAdjustment(); // Valid only for loss calculation.
        // Adjust the unit cost.
        UnitCost *= CCC;
    }

    // If account currency == pair's base currency, adjust UnitCost to future rate (SL). Works only for Forex pairs.
    if ((AccountCurrency == BaseCurrency) && ((CalcMode == SYMBOL_CALC_MODE_FOREX) || (CalcMode == SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE)))
    {
        double current_rate = 1, future_rate = 1;
        if (dir == ORDER_TYPE_BUY)
        {
            if (entry == 0) current_rate = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            else current_rate = entry;
            future_rate = current_rate - SL * _Point;
        }
        else if (dir == ORDER_TYPE_SELL)
        {
            if (entry == 0) current_rate = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            else current_rate = entry;
            future_rate = current_rate + SL * _Point;
        }
        if (future_rate == 0) future_rate = _Point; // Zero divide prevention.
        UnitCost *= (current_rate / future_rate);
    }

    double TickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double LotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    int LotStep_digits = CountDecimalPlaces(LotStep);
    if ((SL != 0) && (UnitCost != 0) && (TickSize != 0)) PositionSize = NormalizeDouble(RiskMoney / (SL * _Point * UnitCost / TickSize), LotStep_digits);

    if (PositionSize < SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN))
    {
        Print("Calculated position size (" + DoubleToString(PositionSize, 2) + ") is less than minimum position size (" + DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN), 2) + "). Setting position size to minimum.");
        PositionSize = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    }
    else if (PositionSize > SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX))
    {
        Print("Calculated position size (" + DoubleToString(PositionSize, 2) + ") is greater than maximum position size (" + DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX), 2) + "). Setting position size to maximum.");
        PositionSize = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    }

    double steps = PositionSize / LotStep;
    if (MathAbs(MathRound(steps) - steps) < 0.00000001) steps = MathRound(steps);
    if (steps - MathFloor(steps) > LotStep / 2)
    {
        Print("Calculated position size (" + DoubleToString(PositionSize, 2) + ") uses uneven step size. Allowed step size = " + DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP), 2) + ". Setting position size to " + DoubleToString(MathFloor(steps) * LotStep, 2) + ".");
        PositionSize = MathFloor(steps) * LotStep;
    }

    return PositionSize;
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