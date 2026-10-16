//+------------------------------------------------------------------+
//|                                              BenTrader.mq5       |
//|                  Manual trading EA with on-chart control panel.  |
//|                                                                  |
//|  Features:                                                       |
//|    • One-click Buy / Sell with default SL distance               |
//|    • Close Profitable / Losing / All (filtered to symbol)        |
//|    • New SL / TP override fields (applied on Enter to all open)  |
//|    • Lot-size preset buttons (configurable, semicolon-separated) |
//|    • Live Bid price + cumulative P&L display                     |
//|    • Local clock in 12-hour AM/PM format                         |
//|    • Light / Dark chart theme toggle                             |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

//==================================================================
//  INPUT PARAMETERS
//==================================================================
input double InpLotSize      = 0.06;                                 // Default Lot Size
input double InpSLDistance   = 15.0;                                 // Default SL Distance (price units)
input double InpProfitFactor = 2.0;                                  // Default Profit Factor (unused for new orders; kept for future)
input string InpLotPresets   = "0.01;0.03;0.06;0.12;0.24;0.36";       // Lot size presets (semicolon-separated)
input int    InpMaxTradeRows = 20;                                    // Max rows in trade panel

//==================================================================
//  UI CONSTANTS
//==================================================================

//--- Standard sizes
#define BTN_WIDTH          200
#define BTN_HEIGHT          50
#define EDIT_WIDTH         150
#define EDIT_HEIGHT         60

//--- Fonts
#define FONT_NAME          "Arial Bold"
#define FONT_SIZE_LABEL     11
#define FONT_SIZE_EDIT      11
#define FONT_SIZE_PRESET     8
#define FONT_SIZE_PRICE     22
#define FONT_SIZE_PNL       18

//--- Right input panel — aligned to Buy/Sell buttons above
#define PANEL_LEFT_X       1070
#define PANEL_RIGHT_X      1480
#define PANEL_WIDTH        (PANEL_RIGHT_X - PANEL_LEFT_X)

//--- Price panel — aligned to "Close Losing" left edge and "Close All" right edge
#define PRICE_PANEL_LEFT_X    650
#define PRICE_PANEL_RIGHT_X  1060
#define PRICE_PANEL_WIDTH    (PRICE_PANEL_RIGHT_X - PRICE_PANEL_LEFT_X)

//--- Trade panel — table view of open trades
//    Left edge aligned with clock (X=20), right edge aligned with
//    Close Profitable right edge (X=440+200=640).
#define TRADE_PANEL_LEFT_X    20
#define TRADE_PANEL_RIGHT_X   640
#define TRADE_PANEL_WIDTH     (TRADE_PANEL_RIGHT_X - TRADE_PANEL_LEFT_X)
#define TRADE_PANEL_TOP_Y     PANEL_ROW_TOP
#define TRADE_ROW_HEIGHT      40
#define TRADE_HEADER_HEIGHT   45
#define TRADE_MAX_ROWS_HARD_CAP 100  // Hard cap for array sizing
int TRADE_MAX_ROWS = 20;             // Set from InpMaxTradeRows in OnInit
#define TRADE_COLS             6    // Checkbox, Type, Vol, Price, SL, P/L

//    Column widths — must sum to TRADE_PANEL_WIDTH (620)
#define TRADE_COL_CHK_W       40
#define TRADE_COL_TYPE_W      60
#define TRADE_COL_VOL_W      100
#define TRADE_COL_PRICE_W    170
#define TRADE_COL_SL_W       170
#define TRADE_COL_PL_W        80

//    Absolute X positions of each column's left edge
#define TRADE_COL_CHK_X       TRADE_PANEL_LEFT_X
#define TRADE_COL_TYPE_X      (TRADE_COL_CHK_X + TRADE_COL_CHK_W)
#define TRADE_COL_VOL_X       (TRADE_COL_TYPE_X + TRADE_COL_TYPE_W)
#define TRADE_COL_PRICE_X     (TRADE_COL_VOL_X + TRADE_COL_VOL_W)
#define TRADE_COL_SL_X        (TRADE_COL_PRICE_X + TRADE_COL_PRICE_W)
#define TRADE_COL_PL_X        (TRADE_COL_SL_X + TRADE_COL_SL_W)

//--- Internal panel layout
#define PANEL_PADDING       20
#define LABEL_AREA_WIDTH   200
#define LABEL_EDIT_GAP      20
#define LABEL_X            PANEL_PADDING
#define EDIT_X             (LABEL_X + LABEL_AREA_WIDTH + LABEL_EDIT_GAP)

//--- Lot preset row
#define PRESET_COUNT        6
#define PRESET_BTN_HEIGHT  36
#define PRESET_BTN_GAP     10
#define PRESET_ROW_GAP     10

//--- Vertical layout — derived from above
#define ROW1_Y              40                                            // Top buttons row
#define BTN_PANEL_GAP       30                                            // Between buttons and panel
#define ROW_HEIGHT          (EDIT_HEIGHT + 10)

#define ROW_PRESET_Y        (ROW1_Y + BTN_HEIGHT + BTN_PANEL_GAP)
#define ROW2_Y              (ROW_PRESET_Y + PRESET_BTN_HEIGHT + PRESET_ROW_GAP)
#define ROW3_Y              (ROW2_Y + ROW_HEIGHT)
#define ROW4_Y              (ROW3_Y + ROW_HEIGHT)

#define PANEL_ROW_TOP       ROW_PRESET_Y
#define PANEL_ROW_BOTTOM    ROW4_Y

#define LABEL_Y_OFFSET      ((EDIT_HEIGHT / 2) - (FONT_SIZE_LABEL / 2) - 2)

//--- Timer
#define TIMER_INTERVAL_SEC  60      // Clock refresh; price/P&L use OnTick

//==================================================================
//  OBJECT NAMES
//==================================================================
#define EDIT_LOT            "EditLotSize"
#define LABEL_LOT           "LabelLotSize"
#define EDIT_NEWSL          "EditNewSL"
#define LABEL_NEWSL         "LabelNewSL"
#define EDIT_NEWTP          "EditNewTP"
#define LABEL_NEWTP         "LabelNewTP"

#define BTN_BUY             "BuyButton"
#define BTN_SELL            "SellButton"
#define BTN_CLOSE_PROFIT    "CloseProfit"
#define BTN_CLOSE_LOSS      "CloseLoss"
#define BTN_CLOSE_ALL       "CloseAll"
#define BTN_THEME           "ThemeButton"
#define BTN_CLEAR_SL        "ClearSLButton"
#define BTN_REMOVE_SL       "RemoveSLButton"
#define BTN_CLOSE_SELECTED  "CloseSelectedButton"

#define LABEL_CLOCK         "ClockLabel"
#define PANEL_BG            "PanelBackground"
#define PRICE_PANEL_BG      "PricePanelBackground"
#define PRICE_LABEL         "PriceLabel"
#define PNL_LABEL           "PnLLabel"
#define PRESET_BTN_PREFIX   "LotPresetBtn_"
#define TRADE_PANEL_BG      "TradePanelBackground"
#define TRADE_GRID_PREFIX   "TradeGrid_"      // Grid separator lines
#define TRADE_HDR_PREFIX    "TradeHdr_"        // Header cells (4 columns)
#define TRADE_CELL_PREFIX   "TradeCell_"       // Data cells: TradeCell_<row>_<col>
#define TRADE_CHK_PREFIX    "TradeChk_"        // Row checkboxes (visual only)

//==================================================================
//  GLOBALS
//==================================================================
CTrade trade;
bool   gIsDarkMode = true;            // EA starts in dark mode
double gPresetValues[PRESET_COUNT];   // Parsed preset values
int    gPresetActualCount = 0;        // Count of validly parsed presets
bool   gTradeChecked[100];            // Checkbox state per trade-panel row (sized to TRADE_MAX_ROWS_HARD_CAP)
ulong  gTradeRowTicket[100];          // Ticket currently displayed at each row (0 = empty row)
bool   gSelectAllChecked = false;     // State of the header "select all" checkbox
#define TRADE_CHK_ALL       "TradeChkAll"

//--- Cached values (set once, re-used on every tick)
int    gSymDigits = 2;                 // Cached SYMBOL_DIGITS (refreshed in OnInit)
int    gGridCount = 0;                 // Actual number of grid lines created
string gTradePrefix[100];              // Pre-built "TradeCell_<r>_" prefixes to avoid recomputation

//--- Commission cache (commissions don't change after a position opens)
#define COMM_CACHE_SIZE  200
ulong  gCommTicket[COMM_CACHE_SIZE];
double gCommValue [COMM_CACHE_SIZE];
int    gCommCount = 0;

//--- Per-row display cache (change detection; avoid redundant ObjectSet*)
ulong  gRowCacheTicket[100];           // ticket last displayed on this row (0 = empty)
string gRowCacheTypeStr[100];
string gRowCacheVolStr[100];
string gRowCachePriceStr[100];
string gRowCacheSLStr[100];
string gRowCachePnLStr[100];
color  gRowCacheColor[100];

//==================================================================
//  LIFECYCLE
//==================================================================

//+------------------------------------------------------------------+
//| Expert initialization: create UI, parse inputs, apply theme,     |
//| start timer.                                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Clamp user-provided row count to the hard cap
   TRADE_MAX_ROWS = MathMax(1, MathMin(InpMaxTradeRows, TRADE_MAX_ROWS_HARD_CAP));

   // Cache values that are expensive to query but rarely change
   gSymDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   for(int r = 0; r < TRADE_MAX_ROWS_HARD_CAP; r++)
   {
      gTradePrefix[r]      = TRADE_CELL_PREFIX + IntegerToString(r) + "_";
      gRowCacheTicket[r]   = 0;
      gRowCacheTypeStr[r]  = "";
      gRowCacheVolStr[r]   = "";
      gRowCachePriceStr[r] = "";
      gRowCacheSLStr[r]    = "";
      gRowCachePnLStr[r]   = "";
      gRowCacheColor[r]    = clrBlack;
   }

   CreateBackgroundPanels();
   CreateTopButtonRow();
   CreateLotPresetRow();
   CreatePanelInputRows();

   SetDarkTheme();
   RefreshAllLabels();

   EventSetTimer(TIMER_INTERVAL_SEC);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Tick handler: single-pass refresh of all live labels.            |
//| Collects open positions ONCE and feeds both the P&L label and    |
//| the trade panel from the shared data.                            |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdatePriceLabel();
   RefreshLiveData();
}

//+------------------------------------------------------------------+
//| Timer handler: refresh slow-changing data (clock).               |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateClock();
}

//+------------------------------------------------------------------+
//| Deinitialization: clean up all chart objects and stop timer.     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteAllUIObjects();
}

//==================================================================
//  CHART EVENT DISPATCH
//==================================================================

//+------------------------------------------------------------------+
//| Top-level chart event dispatcher. Routes events to handlers      |
//| based on type and source object.                                 |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
      HandleObjectClick(sparam);
   else if(id == CHARTEVENT_OBJECT_ENDEDIT)
      HandleObjectEndEdit(sparam);
}

//+------------------------------------------------------------------+
//| Route a button click to the correct handler.                     |
//+------------------------------------------------------------------+
void HandleObjectClick(const string &sparam)
{
   // Fast prefix checks via StringCompare on a known length —
   // avoids StringFind's linear scan.
   int plen = StringLen(PRESET_BTN_PREFIX);
   if(StringLen(sparam) > plen && StringCompare(StringSubstr(sparam, 0, plen), PRESET_BTN_PREFIX) == 0)
   {
      HandlePresetClick(sparam);
      return;
   }

   if(sparam == TRADE_CHK_ALL)
   {
      HandleSelectAllClick();
      return;
   }

   int clen = StringLen(TRADE_CHK_PREFIX);
   if(StringLen(sparam) > clen && StringCompare(StringSubstr(sparam, 0, clen), TRADE_CHK_PREFIX) == 0)
   {
      HandleTradeCheckboxClick(sparam);
      return;
   }

   if(sparam == BTN_BUY)            HandleBuy();
   else if(sparam == BTN_SELL)      HandleSell();
   else if(sparam == BTN_CLOSE_PROFIT
        || sparam == BTN_CLOSE_LOSS
        || sparam == BTN_CLOSE_ALL) HandleCloseAction(sparam);
   else if(sparam == BTN_THEME)     HandleThemeToggle();
   else if(sparam == BTN_CLEAR_SL)  HandleClearSL();
   else if(sparam == BTN_REMOVE_SL) HandleRemoveAllSL();
   else if(sparam == BTN_CLOSE_SELECTED) HandleCloseSelected();

   ResetButtonState(sparam);
}

//+------------------------------------------------------------------+
//| Route end-edit (Enter / focus loss) to the correct handler.      |
//+------------------------------------------------------------------+
void HandleObjectEndEdit(const string &sparam)
{
   if(sparam == EDIT_LOT)         HighlightActivePreset();
   else if(sparam == EDIT_NEWSL)  HandleNewSLEntered();
   else if(sparam == EDIT_NEWTP)  HandleNewTPEntered();
}

//+------------------------------------------------------------------+
//| Reset a button's pressed-state so it doesn't appear "stuck".     |
//+------------------------------------------------------------------+
void ResetButtonState(const string &btnName)
{
   if(ObjectFind(0, btnName) >= 0)
      ObjectSetInteger(0, btnName, OBJPROP_STATE, false);
}

//==================================================================
//  ACTION HANDLERS — TRADING
//==================================================================

//+------------------------------------------------------------------+
//| Place a Buy at market with default SL and no TP.                 |
//+------------------------------------------------------------------+
void HandleBuy()
{
   double lot   = GetChartLot();
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl    = price - InpSLDistance;

   Print("Buy clicked at price ", price, " | Lot: ", lot, " | SL: ", sl);
   trade.Buy(lot, _Symbol, price, sl, 0, "Buy Script");
}

//+------------------------------------------------------------------+
//| Place a Sell at market with default SL and no TP.                |
//+------------------------------------------------------------------+
void HandleSell()
{
   double lot   = GetChartLot();
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl    = price + InpSLDistance;

   Print("Sell clicked at price ", price, " | Lot: ", lot, " | SL: ", sl);
   trade.Sell(lot, _Symbol, price, sl, 0, "Sell Script");
}

//+------------------------------------------------------------------+
//| Close positions matching the action's criterion. Clears the      |
//| New SL field afterward so a leftover value isn't reapplied.      |
//+------------------------------------------------------------------+
void HandleCloseAction(const string &action)
{
   double bidNow = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double askNow = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   Print(GetCloseActionName(action), " clicked | Bid: ", bidNow, " | Ask: ", askNow);

   CloseMatchingPositions(action);

   ObjectSetString(0, EDIT_NEWSL, OBJPROP_TEXT, "");
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Human-friendly name for a close action (for logging).            |
//+------------------------------------------------------------------+
string GetCloseActionName(const string &action)
{
   if(action == BTN_CLOSE_ALL)    return "Close All";
   if(action == BTN_CLOSE_PROFIT) return "Close Profitable";
   if(action == BTN_CLOSE_LOSS)   return "Close Losing";
   return action;
}

//+------------------------------------------------------------------+
//| Iterate open positions on the current symbol and close those     |
//| matching the close-action criterion.                             |
//+------------------------------------------------------------------+
void CloseMatchingPositions(const string &action)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double netProfit = GetPositionNetProfit(ticket);
      if(ShouldClose(action, netProfit))
      {
         Print("Trade closed because of ", GetCloseActionName(action),
               " — ticket #", ticket, " P&L: ", DoubleToString(netProfit, 2));
         trade.PositionClose(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Decide if a position with the given net profit should be closed  |
//| under the given action.                                          |
//+------------------------------------------------------------------+
bool ShouldClose(const string &action, double netProfit)
{
   if(action == BTN_CLOSE_ALL)                        return true;
   if(action == BTN_CLOSE_PROFIT && netProfit > 0)    return true;
   if(action == BTN_CLOSE_LOSS   && netProfit < 0)    return true;
   return false;
}

//+------------------------------------------------------------------+
//| Net P&L for the currently selected position: profit + swap +     |
//| commission.                                                      |
//+------------------------------------------------------------------+
double GetPositionNetProfit(ulong ticket)
{
   // Uses cached commission to avoid re-scanning deal history every call.
   return PositionGetDouble(POSITION_PROFIT)
        + PositionGetDouble(POSITION_SWAP)
        + GetPositionCommissionCached(ticket);
}

//+------------------------------------------------------------------+
//| Sum commissions for a specific position from deal history.       |
//+------------------------------------------------------------------+
double GetPositionCommission(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return 0;
   long pos_id = PositionGetInteger(POSITION_IDENTIFIER);

   if(!HistorySelectByPosition(pos_id)) return 0;

   double comm = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      comm += HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
   }
   return comm;
}

//==================================================================
//  ACTION HANDLERS — SL / TP MODIFICATION
//==================================================================

//+------------------------------------------------------------------+
//| Handle Enter pressed (or focus-loss) on the New SL field.        |
//+------------------------------------------------------------------+
void HandleNewSLEntered()
{
   string inputText = ObjectGetString(0, EDIT_NEWSL, OBJPROP_TEXT);
   double newSL = StringToDouble(inputText);

   if(newSL <= 0)
   {
      Print("New SL: Invalid price entered — ", inputText);
      return;
   }

   ApplyNewSLToAllPositions(newSL);
}

//+------------------------------------------------------------------+
//| Apply a new SL to all open positions on the current symbol.      |
//| Closes positions whose SL is already reached.                    |
//+------------------------------------------------------------------+
void ApplyNewSLToAllPositions(double newSL)
{
   // Build a set of checked tickets from the trade panel; skip silently if none checked
   ulong checkedTickets[];
   int checkedCount = 0;
   for(int r = 0; r < TRADE_MAX_ROWS; r++)
   {
      if(gTradeChecked[r] && gTradeRowTicket[r] != 0)
      {
         ArrayResize(checkedTickets, checkedCount + 1);
         checkedTickets[checkedCount++] = gTradeRowTicket[r];
      }
   }
   if(checkedCount == 0) return; // no trades selected — do nothing

   int modified = 0, skipped = 0, failed = 0;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID); // reference price for SL validation

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!IsTicketInArray(ticket, checkedTickets, checkedCount)) continue;

      long   posType = PositionGetInteger(POSITION_TYPE);
      double tp      = PositionGetDouble(POSITION_TP);

      // Reject if applying the new SL would trigger position closure.
      // Buy: SL must be strictly below price. Sell: SL must be strictly above price.
      if(WouldSLTriggerClose(posType, newSL, price))
      {
         Print("New SL: Rejected for ticket #", ticket,
               " (", (posType == POSITION_TYPE_BUY ? "Buy" : "Sell"),
               ") — SL ", newSL, " would immediately trigger at price ", price);
         skipped++;
         continue;
      }

      if(trade.PositionModify(ticket, newSL, tp))
         modified++;
      else
      {
         Print("New SL: Failed to modify ticket #", ticket,
               " — Error: ", trade.ResultRetcodeDescription());
         failed++;
      }
   }

   Print("New SL complete — Modified: ", modified,
         "  Skipped (would close): ", skipped,
         "  Failed: ", failed);
}

//+------------------------------------------------------------------+
//| Would applying this SL immediately trigger the position to close?|
//| Buy: SL must be strictly below price (reject if SL >= price).    |
//| Sell: SL must be strictly above price (reject if SL <= price).   |
//+------------------------------------------------------------------+
bool WouldSLTriggerClose(long posType, double newSL, double price)
{
   if(posType == POSITION_TYPE_BUY  && newSL >= price) return true;
   if(posType == POSITION_TYPE_SELL && newSL <= price) return true;
   return false;
}

//+------------------------------------------------------------------+
//| Check if a ticket exists in the given array.                     |
//+------------------------------------------------------------------+
bool IsTicketInArray(ulong ticket, ulong &arr[], int count)
{
   for(int i = 0; i < count; i++)
      if(arr[i] == ticket) return true;
   return false;
}

//+------------------------------------------------------------------+
//| Handle Enter (or focus-loss) on the New TP field.                |
//+------------------------------------------------------------------+
void HandleNewTPEntered()
{
   string inputText = ObjectGetString(0, EDIT_NEWTP, OBJPROP_TEXT);
   double newTP = StringToDouble(inputText);

   if(newTP <= 0)
   {
      Print("New TP: Invalid price entered — ", inputText);
      return;
   }

   ApplyNewTPToAllPositions(newTP);
}

//+------------------------------------------------------------------+
//| Apply a new TP to all open positions on the current symbol.      |
//+------------------------------------------------------------------+
void ApplyNewTPToAllPositions(double newTP)
{
   int modified = 0, failed = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double sl = PositionGetDouble(POSITION_SL);
      if(trade.PositionModify(ticket, sl, newTP))
         modified++;
      else
      {
         Print("New TP: Failed to modify ticket #", ticket,
               " — Error: ", trade.ResultRetcodeDescription());
         failed++;
      }
   }

   Print("New TP complete — Modified: ", modified, "  Failed: ", failed);
}

//+------------------------------------------------------------------+
//| Clear the New SL field (no impact on open positions).            |
//+------------------------------------------------------------------+
void HandleClearSL()
{
   ObjectSetString(0, EDIT_NEWSL, OBJPROP_TEXT, "");
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Remove the SL from all open positions on the current symbol      |
//| (sets SL to 0, which MT5 interprets as "no SL").                 |
//+------------------------------------------------------------------+
void HandleRemoveAllSL()
{
   int modified = 0, failed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double tp = PositionGetDouble(POSITION_TP);
      if(trade.PositionModify(ticket, 0.0, tp))
         modified++;
      else
      {
         Print("Remove All SL: Failed to modify ticket #", ticket,
               " — Error: ", trade.ResultRetcodeDescription());
         failed++;
      }
   }
   Print("Remove All SL complete — Modified: ", modified, "  Failed: ", failed);
}

//+------------------------------------------------------------------+
//| Close only the trades whose row checkbox is checked in the       |
//| trade panel. Skips silently if none are checked.                 |
//+------------------------------------------------------------------+
void HandleCloseSelected()
{
   ulong checkedTickets[];
   int checkedCount = 0;
   for(int r = 0; r < TRADE_MAX_ROWS; r++)
   {
      if(gTradeChecked[r] && gTradeRowTicket[r] != 0)
      {
         ArrayResize(checkedTickets, checkedCount + 1);
         checkedTickets[checkedCount++] = gTradeRowTicket[r];
      }
   }
   if(checkedCount == 0) return; // nothing selected — do nothing

   int closed = 0, failed = 0;
   for(int i = 0; i < checkedCount; i++)
   {
      ulong ticket = checkedTickets[i];
      if(!PositionSelectByTicket(ticket)) continue;
      if(trade.PositionClose(ticket))
         closed++;
      else
      {
         Print("Close Selected: Failed to close ticket #", ticket,
               " — Error: ", trade.ResultRetcodeDescription());
         failed++;
      }
   }
   Print("Close Selected complete — Closed: ", closed, "  Failed: ", failed);
}

//==================================================================
//  ACTION HANDLERS — UI / PRESETS / THEME
//==================================================================

//+------------------------------------------------------------------+
//| Apply the selected preset's lot value to the Lot Size field.     |
//+------------------------------------------------------------------+
void HandlePresetClick(const string &btnName)
{
   int idx = (int)StringToInteger(StringSubstr(btnName, StringLen(PRESET_BTN_PREFIX)));
   if(idx < 0 || idx >= gPresetActualCount) return;

   ObjectSetString(0, EDIT_LOT, OBJPROP_TEXT, DoubleToString(gPresetValues[idx], 2));
   HighlightActivePreset();
}

//+------------------------------------------------------------------+
//| Toggle a trade-panel checkbox state (persists by row index).     |
//+------------------------------------------------------------------+
void HandleTradeCheckboxClick(const string &btnName)
{
   int rowIdx = (int)StringToInteger(StringSubstr(btnName, StringLen(TRADE_CHK_PREFIX)));
   if(rowIdx < 0 || rowIdx >= TRADE_MAX_ROWS) return;

   gTradeChecked[rowIdx] = !gTradeChecked[rowIdx];
   SetTradeCheckboxState(rowIdx, gTradeChecked[rowIdx]);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Toggle all row checkboxes on/off via the header checkbox.        |
//+------------------------------------------------------------------+
void HandleSelectAllClick()
{
   gSelectAllChecked = !gSelectAllChecked;
   SetTradeCheckboxState(-1, gSelectAllChecked);

   for(int i = 0; i < TRADE_MAX_ROWS; i++)
   {
      if(gTradeRowTicket[i] == 0) continue; // skip empty rows
      gTradeChecked[i] = gSelectAllChecked;
      SetTradeCheckboxState(i, gSelectAllChecked);
   }
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Toggle between light and dark chart themes.                      |
//+------------------------------------------------------------------+
void HandleThemeToggle()
{
   if(gIsDarkMode)
   {
      SetLightTheme();
      gIsDarkMode = false;
      ObjectSetString(0, BTN_THEME, OBJPROP_TEXT, "Dark Mode");
   }
   else
   {
      SetDarkTheme();
      gIsDarkMode = true;
      ObjectSetString(0, BTN_THEME, OBJPROP_TEXT, "Light Mode");
   }
}

//==================================================================
//  THEME
//==================================================================

//+------------------------------------------------------------------+
//| Apply the light chart theme (white background, green/red bars).  |
//+------------------------------------------------------------------+
void SetLightTheme()
{
   ChartSetInteger(0, CHART_COLOR_BACKGROUND,  clrWhite);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND,  clrBlack);
   ChartSetInteger(0, CHART_COLOR_GRID,        clrGray);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE,  clrBlack);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrGreen);
   ChartSetInteger(0, CHART_COLOR_CHART_UP,    clrGreen);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrRed);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN,  clrRed);
   ChartSetInteger(0, CHART_COLOR_BID,         clrRed);
   ChartSetInteger(0, CHART_COLOR_ASK,         clrBlue);
   ChartSetInteger(0, CHART_COLOR_LAST,        clrRed);
   ChartSetInteger(0, CHART_COLOR_VOLUME,      clrGreen);
   ChartSetInteger(0, CHART_COLOR_STOP_LEVEL,  clrRed);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Apply the dark chart theme (black background, green/red bars).   |
//+------------------------------------------------------------------+
void SetDarkTheme()
{
   ChartSetInteger(0, CHART_COLOR_BACKGROUND,  clrBlack);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND,  clrWhite);
   ChartSetInteger(0, CHART_COLOR_GRID,        clrGray);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE,  clrWhite);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrGreen);
   ChartSetInteger(0, CHART_COLOR_CHART_UP,    clrGreen);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrRed);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN,  clrRed);
   ChartSetInteger(0, CHART_COLOR_BID,         clrWhite);
   ChartSetInteger(0, CHART_COLOR_ASK,         clrWhite);
   ChartSetInteger(0, CHART_COLOR_LAST,        clrWhite);
   ChartSetInteger(0, CHART_COLOR_VOLUME,      0x333333);
   ChartSetInteger(0, CHART_COLOR_STOP_LEVEL,  clrRed);
   ChartRedraw(0);
}

//==================================================================
//  LIVE LABEL UPDATES
//==================================================================

//+------------------------------------------------------------------+
//| Refresh every dynamic label (called at startup).                 |
//+------------------------------------------------------------------+
void RefreshAllLabels()
{
   UpdateClock();
   UpdatePriceLabel();
   RefreshLiveData();
}

//+------------------------------------------------------------------+
//| Update the price label with the current Bid price.               |
//+------------------------------------------------------------------+
void UpdatePriceLabel()
{
   static double lastBid = -1;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid == lastBid) return;              // skip redraw if unchanged
   lastBid = bid;
   ObjectSetString(0, PRICE_LABEL, OBJPROP_TEXT, DoubleToString(bid, gSymDigits));
}

//+------------------------------------------------------------------+
//| Update the P&L label from a pre-computed total (no re-iteration).|
//+------------------------------------------------------------------+
void SetPnLLabel(double total)
{
   color clr = clrBlack;
   if(total > 0)      clr = clrGreen;
   else if(total < 0) clr = clrRed;

   // Change detection — avoid redundant ObjectSet when value unchanged
   static double  lastTotal = 1e300;
   static color   lastColor = clrNONE;
   if(total != lastTotal)
   {
      ObjectSetString(0, PNL_LABEL, OBJPROP_TEXT, DoubleToString(total, 2));
      lastTotal = total;
   }
   if(clr != lastColor)
   {
      ObjectSetInteger(0, PNL_LABEL, OBJPROP_COLOR, clr);
      lastColor = clr;
   }
}

//+------------------------------------------------------------------+
//| Update the clock label with current local time in 12-hour format.|
//+------------------------------------------------------------------+
void UpdateClock()
{
   MqlDateTime d;
   TimeToStruct(TimeLocal(), d);

   int    h12  = (d.hour % 12 == 0) ? 12 : (d.hour % 12);
   string ampm = (d.hour < 12) ? "AM" : "PM";
   ObjectSetString(0, LABEL_CLOCK, OBJPROP_TEXT,
                   StringFormat("%d:%02d %s", h12, d.min, ampm));
}

//==================================================================
//  LOT PRESETS
//==================================================================

//+------------------------------------------------------------------+
//| Parse the InpLotPresets input string into the gPresetValues      |
//| array. Skips invalid entries and logs them.                      |
//+------------------------------------------------------------------+
void ParseLotPresets()
{
   string parts[];
   int n = StringSplit(InpLotPresets, ';', parts);
   gPresetActualCount = 0;

   for(int i = 0; i < n && gPresetActualCount < PRESET_COUNT; i++)
   {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      double v = StringToDouble(s);

      if(v > 0)
      {
         gPresetValues[gPresetActualCount++] = v;
      }
      else
      {
         Print("Lot Presets: skipping invalid entry \"", s, "\"");
      }
   }
}

//+------------------------------------------------------------------+
//| Create the row of preset buttons spanning the input panel area.  |
//+------------------------------------------------------------------+
void CreateLotPresetButtons(int panelX, int y, int panelWidth)
{
   if(gPresetActualCount == 0) return;

   int usable = panelWidth - (PANEL_PADDING * 2);
   int gaps   = PRESET_BTN_GAP * (gPresetActualCount - 1);
   int btnW   = (usable - gaps) / gPresetActualCount;
   int startX = panelX + PANEL_PADDING;

   for(int i = 0; i < gPresetActualCount; i++)
   {
      CreatePresetButton(PRESET_BTN_PREFIX + IntegerToString(i),
                         startX + i * (btnW + PRESET_BTN_GAP),
                         y, btnW,
                         DoubleToString(gPresetValues[i], 2));
   }
}

//+------------------------------------------------------------------+
//| Create one preset button with consistent styling.                |
//+------------------------------------------------------------------+
void CreatePresetButton(string name, int x, int y, int width, string text)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     PRESET_BTN_HEIGHT);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetString (0, name, OBJPROP_FONT,      FONT_NAME);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  FONT_SIZE_PRESET);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   clrDarkBlue);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clrWhite);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Highlight the preset whose value matches the current Lot Size.   |
//+------------------------------------------------------------------+
void HighlightActivePreset()
{
   double current = StringToDouble(ObjectGetString(0, EDIT_LOT, OBJPROP_TEXT));
   for(int i = 0; i < gPresetActualCount; i++)
   {
      string name  = PRESET_BTN_PREFIX + IntegerToString(i);
      bool   match = (MathAbs(gPresetValues[i] - current) < 0.0001);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR,
                       match ? clrOrange : clrDarkBlue);
   }
   ChartRedraw(0);
}

//==================================================================
//  CHART FIELD ACCESS
//==================================================================

//+------------------------------------------------------------------+
//| Read the lot size from the chart field; fall back to input.      |
//+------------------------------------------------------------------+
double GetChartLot()
{
   double val = StringToDouble(ObjectGetString(0, EDIT_LOT, OBJPROP_TEXT));
   return (val > 0) ? val : InpLotSize;
}

//==================================================================
//  UI CONSTRUCTION
//==================================================================

//+------------------------------------------------------------------+
//| Create the two background panels (right input + price/PnL).      |
//+------------------------------------------------------------------+
void CreateBackgroundPanels()
{
   CreatePanel();
   CreatePricePanel();
   CreateTradePanel();
}

//+------------------------------------------------------------------+
//| Create the top row of action buttons (clock + theme + close      |
//| actions + Buy/Sell + Clear/Remove SL).                           |
//+------------------------------------------------------------------+
void CreateTopButtonRow()
{
   CreateClockLabel(LABEL_CLOCK,    20, ROW1_Y, BTN_WIDTH, BTN_HEIGHT);
   CreateButton(BTN_THEME,         230, ROW1_Y, "Light Mode",       clrDimGray);
   CreateButton(BTN_CLOSE_PROFIT,  440, ROW1_Y, "Close Profitable", clrRoyalBlue);
   CreateButton(BTN_CLOSE_LOSS,    650, ROW1_Y, "Close Losing",     clrOrange);
   CreateButton(BTN_CLOSE_ALL,     860, ROW1_Y, "Close All",        clrPurple);
   CreateButton(BTN_BUY,          1070, ROW1_Y, "Buy",              clrGreen);
   CreateButton(BTN_SELL,         1280, ROW1_Y, "Sell",             clrRed);
   CreateButton(BTN_CLEAR_SL,     1490, ROW1_Y, "Clear SL",         clrSlateGray);
   CreateButton(BTN_REMOVE_SL,    1700, ROW1_Y, "Remove All SL",    clrSlateGray);
   CreateButton(BTN_CLOSE_SELECTED, 1910, ROW1_Y, "Close Selected", clrPurple);
}

//+------------------------------------------------------------------+
//| Parse and lay out the lot-preset shortcut buttons.               |
//+------------------------------------------------------------------+
void CreateLotPresetRow()
{
   ParseLotPresets();
   CreateLotPresetButtons(PANEL_LEFT_X, ROW_PRESET_Y, PANEL_WIDTH);
}

//+------------------------------------------------------------------+
//| Create the Lot Size / New SL / New TP rows inside the right      |
//| input panel, plus an initial preset highlight.                   |
//+------------------------------------------------------------------+
void CreatePanelInputRows()
{
   int dx = PANEL_LEFT_X;

   CreateLabel    (LABEL_LOT,    LABEL_X + dx, ROW2_Y, "Lot Size:");
   CreateEditField(EDIT_LOT,     EDIT_X + dx,  ROW2_Y, EDIT_WIDTH, DoubleToString(InpLotSize, 2));
   HighlightActivePreset();

   CreateLabel    (LABEL_NEWSL,  LABEL_X + dx, ROW3_Y, "New SL:");
   CreateEditField(EDIT_NEWSL,   EDIT_X + dx,  ROW3_Y, EDIT_WIDTH, "");

   CreateLabel    (LABEL_NEWTP,  LABEL_X + dx, ROW4_Y, "New TP:");
   CreateEditField(EDIT_NEWTP,   EDIT_X + dx,  ROW4_Y, EDIT_WIDTH, "");
}

//+------------------------------------------------------------------+
//| Create the right-side background panel.                          |
//+------------------------------------------------------------------+
void CreatePanel()
{
   int h = (PANEL_ROW_BOTTOM + EDIT_HEIGHT) - PANEL_ROW_TOP + (PANEL_PADDING * 2);
   int y = PANEL_ROW_TOP - PANEL_PADDING;
   CreateRectangleLabel(PANEL_BG, PANEL_LEFT_X, y, PANEL_WIDTH, h);
}

//+------------------------------------------------------------------+
//| Create the left price panel + price label + P&L label.           |
//+------------------------------------------------------------------+
void CreatePricePanel()
{
   int h = (PANEL_ROW_BOTTOM + EDIT_HEIGHT) - PANEL_ROW_TOP + (PANEL_PADDING * 2);
   int y = PANEL_ROW_TOP - PANEL_PADDING;
   int w = PRICE_PANEL_WIDTH;

   CreateRectangleLabel(PRICE_PANEL_BG, PRICE_PANEL_LEFT_X, y, w, h);

   int centerX = PRICE_PANEL_LEFT_X + (w / 2);
   int priceY  = y + (h / 4);            // center of top half
   int pnlY    = y + (h * 3 / 4);        // center of bottom half

   CreateCenteredLabel(PRICE_LABEL, centerX, priceY, "—",    FONT_SIZE_PRICE);
   CreateCenteredLabel(PNL_LABEL,   centerX, pnlY,  "0.00", FONT_SIZE_PNL);
}

//+------------------------------------------------------------------+
//| Create a styled rectangle label used as a panel background.      |
//+------------------------------------------------------------------+
void CreateRectangleLabel(string name, int x, int y, int width, int height)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    clrGainsboro);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clrSilver);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Create a centered, bold label (used for price and P&L).          |
//+------------------------------------------------------------------+
void CreateCenteredLabel(string name, int x, int y, string text, int fontSize)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,    ANCHOR_CENTER);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetString (0, name, OBJPROP_FONT,      FONT_NAME);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clrBlack);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Create the trade panel: background, header, and empty row slots. |
//| Rows are populated dynamically in UpdateTradePanel().            |
//+------------------------------------------------------------------+
void CreateTradePanel()
{
   int panelY      = TRADE_PANEL_TOP_Y - PANEL_PADDING;
   int panelH      = PANEL_PADDING + TRADE_HEADER_HEIGHT + (TRADE_ROW_HEIGHT * TRADE_MAX_ROWS) + PANEL_PADDING;

   // Background
   CreateRectangleLabel(TRADE_PANEL_BG, TRADE_PANEL_LEFT_X, panelY, TRADE_PANEL_WIDTH, panelH);

   // Header row cells (bold)
   int headerY = panelY + PANEL_PADDING;
   CreateTradeCheckbox(TRADE_CHK_ALL,
                       TRADE_COL_CHK_X + (TRADE_COL_CHK_W - 20) / 2,
                       headerY + (TRADE_HEADER_HEIGHT - 20) / 2, 20);
   CreateTradeCell(TRADE_HDR_PREFIX + "1", TRADE_COL_TYPE_X,  headerY, TRADE_COL_TYPE_W,  TRADE_HEADER_HEIGHT, "Type",  true);
   CreateTradeCell(TRADE_HDR_PREFIX + "2", TRADE_COL_VOL_X,   headerY, TRADE_COL_VOL_W,   TRADE_HEADER_HEIGHT, "Vol",   true);
   CreateTradeCell(TRADE_HDR_PREFIX + "3", TRADE_COL_PRICE_X, headerY, TRADE_COL_PRICE_W, TRADE_HEADER_HEIGHT, "Price", true);
   CreateTradeCell(TRADE_HDR_PREFIX + "4", TRADE_COL_SL_X,    headerY, TRADE_COL_SL_W,    TRADE_HEADER_HEIGHT, "SL",    true);
   CreateTradeCell(TRADE_HDR_PREFIX + "5", TRADE_COL_PL_X,    headerY, TRADE_COL_PL_W,    TRADE_HEADER_HEIGHT, "P/L",   true);

   // Data-row cells (pre-created empty)
   for(int r = 0; r < TRADE_MAX_ROWS; r++)
   {
      int rowY = headerY + TRADE_HEADER_HEIGHT + (r * TRADE_ROW_HEIGHT);
      string rp = TRADE_CELL_PREFIX + IntegerToString(r) + "_";
      // Column 0: visual checkbox (pre-drawn rectangle in the cell)
      CreateTradeCheckbox(TRADE_CHK_PREFIX + IntegerToString(r),
                          TRADE_COL_CHK_X + (TRADE_COL_CHK_W - 20) / 2,
                          rowY + (TRADE_ROW_HEIGHT - 20) / 2, 20);
      CreateTradeCell(rp + "1", TRADE_COL_TYPE_X,  rowY, TRADE_COL_TYPE_W,  TRADE_ROW_HEIGHT, " ", false);
      CreateTradeCell(rp + "2", TRADE_COL_VOL_X,   rowY, TRADE_COL_VOL_W,   TRADE_ROW_HEIGHT, " ", false);
      CreateTradeCell(rp + "3", TRADE_COL_PRICE_X, rowY, TRADE_COL_PRICE_W, TRADE_ROW_HEIGHT, " ", false);
      CreateTradeCell(rp + "4", TRADE_COL_SL_X,    rowY, TRADE_COL_SL_W,    TRADE_ROW_HEIGHT, " ", false);
      CreateTradeCell(rp + "5", TRADE_COL_PL_X,    rowY, TRADE_COL_PL_W,    TRADE_ROW_HEIGHT, " ", false);
   }

   CreateTradePanelGrid(panelY, headerY, panelH);
}

//+------------------------------------------------------------------+
//| Draw the grid separators (column borders + row separators) that  |
//| turn the labels into a table look.                               |
//+------------------------------------------------------------------+
void CreateTradePanelGrid(int panelY, int headerY, int panelH)
{
   int gridIdx = 0;
   int lineColor = (int)clrDarkGray;
   int endY = headerY + TRADE_HEADER_HEIGHT + (TRADE_ROW_HEIGHT * TRADE_MAX_ROWS);

   // Vertical column dividers (5 lines between 6 columns)
   int vxs[] = {TRADE_COL_TYPE_X, TRADE_COL_VOL_X, TRADE_COL_PRICE_X, TRADE_COL_SL_X, TRADE_COL_PL_X};
   for(int i = 0; i < ArraySize(vxs); i++)
   {
      CreateTradeGridLine(TRADE_GRID_PREFIX + IntegerToString(gridIdx++),
                          vxs[i], headerY, 1, endY - headerY, lineColor);
   }

   // Horizontal line under header
   CreateTradeGridLine(TRADE_GRID_PREFIX + IntegerToString(gridIdx++),
                       TRADE_PANEL_LEFT_X, headerY + TRADE_HEADER_HEIGHT,
                       TRADE_PANEL_WIDTH, 1, lineColor);

   // Horizontal lines between data rows
   for(int r = 1; r < TRADE_MAX_ROWS; r++)
   {
      int lineY = headerY + TRADE_HEADER_HEIGHT + (r * TRADE_ROW_HEIGHT);
      CreateTradeGridLine(TRADE_GRID_PREFIX + IntegerToString(gridIdx++),
                          TRADE_PANEL_LEFT_X, lineY, TRADE_PANEL_WIDTH, 1, lineColor);
   }
   gGridCount = gridIdx;  // record exact count for OnDeinit cleanup
}

//+------------------------------------------------------------------+
//| Create a thin rectangle label used as a grid line.               |
//+------------------------------------------------------------------+
void CreateTradeGridLine(string name, int x, int y, int width, int height, int clr)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Create one table cell (a bordered rectangle-styled label). Text  |
//| is anchored inside so it never overflows the panel.              |
//+------------------------------------------------------------------+
void CreateTradeCell(string name, int x, int y, int width, int height, string text, bool isHeader)
{
   // Centered text label placed inside the cell
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x + width / 2);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y + height / 2);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,    ANCHOR_CENTER);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetString (0, name, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  isHeader ? 11 : 10);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clrBlack);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Create a visual (non-interactive) checkbox — a small square      |
//| outline. Purely decorative for now.                              |
//+------------------------------------------------------------------+
void CreateTradeCheckbox(string name, int x, int y, int size)
{
   // Use an OBJ_BUTTON so clicks are received. Styled to look like a checkbox.
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        size);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        size);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      clrWhite);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        clrBlack);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetString (0, name, OBJPROP_TEXT,         " ");
   ObjectSetString (0, name, OBJPROP_FONT,         "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,     11);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
}

//+------------------------------------------------------------------+
//| Update a checkbox's visual state (checked = blue with tick,      |
//| unchecked = white and empty).                                    |
//+------------------------------------------------------------------+
void SetTradeCheckboxState(int rowIdx, bool checked)
{
   string name = (rowIdx == -1) ? TRADE_CHK_ALL : (TRADE_CHK_PREFIX + IntegerToString(rowIdx));
   if(checked)
   {
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrDodgerBlue);
      ObjectSetInteger(0, name, OBJPROP_COLOR,   clrWhite);
      ObjectSetString (0, name, OBJPROP_TEXT,    CharToString(0xFC) ); // Wingdings check
      ObjectSetString (0, name, OBJPROP_FONT,    "Wingdings");
   }
   else
   {
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrWhite);
      ObjectSetInteger(0, name, OBJPROP_COLOR,   clrBlack);
      ObjectSetString (0, name, OBJPROP_TEXT,    " ");
      ObjectSetString (0, name, OBJPROP_FONT,    "Arial Bold");
   }
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
}

//+------------------------------------------------------------------+
//| Cached commission lookup. Commissions don't change after a       |
//| position opens, so once we've read the deal history for a given  |
//| ticket we never read it again. This removes the per-tick history |
//| scan that was the biggest hot-path cost.                         |
//+------------------------------------------------------------------+
double GetPositionCommissionCached(ulong ticket)
{
   for(int i = 0; i < gCommCount; i++)
      if(gCommTicket[i] == ticket) return gCommValue[i];

   // Not cached — compute (expensive) and store
   double c = GetPositionCommission(ticket);
   if(gCommCount < COMM_CACHE_SIZE)
   {
      gCommTicket[gCommCount] = ticket;
      gCommValue [gCommCount] = c;
      gCommCount++;
   }
   return c;
}

//+------------------------------------------------------------------+
//| Collect every open position on the current symbol in ONE pass.   |
//| Fills parallel arrays with ticket/type/vol/open/sl/pnl, returns  |
//| the count and the summed P&L via out-param. Caller supplies      |
//| pre-sized arrays (no dynamic resizing in the hot path).          |
//+------------------------------------------------------------------+
int CollectPositions(ulong &tickets[], long &types[], double &vols[],
                     double &opens[], double &sls[], double &pnls[],
                     double &totalPnL)
{
   int total = PositionsTotal();
   int count = 0;
   totalPnL  = 0;

   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double pnl = PositionGetDouble(POSITION_PROFIT)
                 + PositionGetDouble(POSITION_SWAP)
                 + GetPositionCommissionCached(ticket);

      tickets[count] = ticket;
      types  [count] = PositionGetInteger(POSITION_TYPE);
      vols   [count] = PositionGetDouble (POSITION_VOLUME);
      opens  [count] = PositionGetDouble (POSITION_PRICE_OPEN);
      sls    [count] = PositionGetDouble (POSITION_SL);
      pnls   [count] = pnl;
      totalPnL += pnl;
      count++;
      if(count >= TRADE_MAX_ROWS_HARD_CAP) break;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Insertion sort of parallel arrays by opens[] descending.         |
//| Insertion sort is O(n) on nearly-sorted data — ideal here since  |
//| the order changes only when positions are added/removed.         |
//+------------------------------------------------------------------+
void SortByPriceDescending(ulong &tickets[], long &types[], double &vols[],
                           double &opens[], double &sls[], double &pnls[],
                           int count)
{
   for(int i = 1; i < count; i++)
   {
      double op = opens[i];
      ulong  t  = tickets[i];
      long   ty = types[i];
      double v  = vols[i];
      double s  = sls[i];
      double pl = pnls[i];

      int j = i - 1;
      while(j >= 0 && opens[j] < op)
      {
         opens  [j+1] = opens[j];
         tickets[j+1] = tickets[j];
         types  [j+1] = types[j];
         vols   [j+1] = vols[j];
         sls    [j+1] = sls[j];
         pnls   [j+1] = pnls[j];
         j--;
      }
      opens  [j+1] = op;
      tickets[j+1] = t;
      types  [j+1] = ty;
      vols   [j+1] = v;
      sls    [j+1] = s;
      pnls   [j+1] = pl;
   }
}

//+------------------------------------------------------------------+
//| Single-pass refresh: collect open positions once, sort by Price  |
//| descending, update the P&L label and the trade panel from the    |
//| cached data. Uses per-row change detection to avoid redundant    |
//| ObjectSet* calls when values haven't changed since last tick.    |
//+------------------------------------------------------------------+
void RefreshLiveData()
{
   // Pre-sized fixed arrays — no dynamic ArrayResize in the hot path
   ulong  tickets[100];
   long   types  [100];
   double vols   [100];
   double opens  [100];
   double sls    [100];
   double pnls   [100];
   double totalPnL = 0;

   int count = CollectPositions(tickets, types, vols, opens, sls, pnls, totalPnL);
   SortByPriceDescending(tickets, types, vols, opens, sls, pnls, count);

   SetPnLLabel(totalPnL);
   PopulateTradePanel(tickets, types, vols, opens, sls, pnls, count);
}

//+------------------------------------------------------------------+
//| Populate the trade panel rows with pre-collected data, writing   |
//| only to cells that changed since the previous refresh.           |
//+------------------------------------------------------------------+
void PopulateTradePanel(ulong &tickets[], long &types[], double &vols[],
                        double &opens[], double &sls[], double &pnls[],
                        int count)
{
   int digits = gSymDigits;

   for(int r = 0; r < TRADE_MAX_ROWS; r++)
   {
      if(r < count)
      {
         ulong  ticket  = tickets[r];
         string typeStr = (types[r] == POSITION_TYPE_BUY) ? "B" : "S";
         string volStr  = DoubleToString(vols[r], 2);
         string priStr  = DoubleToString(opens[r], digits);
         string slStr   = (sls[r] > 0) ? DoubleToString(sls[r], digits) : "-";
         string pnlStr  = DoubleToString(pnls[r], 2);
         color  clr     = (pnls[r] > 0) ? clrGreen : (pnls[r] < 0 ? clrRed : clrBlack);

         bool colorChanged = (gRowCacheColor[r] != clr);
         string rp = gTradePrefix[r];

         if(colorChanged || gRowCacheTicket[r]  != ticket || gRowCacheTypeStr[r] != typeStr)
         { SetTradeCell(rp + "1", typeStr, clr); gRowCacheTypeStr[r] = typeStr; }

         if(colorChanged || gRowCacheVolStr[r] != volStr)
         { SetTradeCell(rp + "2", volStr, clr);  gRowCacheVolStr[r]  = volStr; }

         if(colorChanged || gRowCachePriceStr[r] != priStr)
         { SetTradeCell(rp + "3", priStr, clr);  gRowCachePriceStr[r] = priStr; }

         if(colorChanged || gRowCacheSLStr[r] != slStr)
         { SetTradeCell(rp + "4", slStr, clr);   gRowCacheSLStr[r]   = slStr; }

         if(colorChanged || gRowCachePnLStr[r] != pnlStr)
         { SetTradeCell(rp + "5", pnlStr, clr);  gRowCachePnLStr[r]  = pnlStr; }

         gRowCacheColor[r]  = clr;
         gRowCacheTicket[r] = ticket;
         gTradeRowTicket[r] = ticket;
      }
      else if(gRowCacheTicket[r] != 0)
      {
         // Row went from occupied to empty — clear it once
         string rp = gTradePrefix[r];
         SetTradeCell(rp + "1", " ", clrBlack);
         SetTradeCell(rp + "2", " ", clrBlack);
         SetTradeCell(rp + "3", " ", clrBlack);
         SetTradeCell(rp + "4", " ", clrBlack);
         SetTradeCell(rp + "5", " ", clrBlack);
         gRowCacheTicket[r]   = 0;
         gRowCacheTypeStr[r]  = " ";
         gRowCacheVolStr[r]   = " ";
         gRowCachePriceStr[r] = " ";
         gRowCacheSLStr[r]    = " ";
         gRowCachePnLStr[r]   = " ";
         gRowCacheColor[r]    = clrBlack;
         gTradeRowTicket[r]   = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Set text and color on one trade-panel cell.                      |
//+------------------------------------------------------------------+
void SetTradeCell(string name, string text, color clr)
{
   ObjectSetString (0, name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Create the clock element styled as a non-clickable button.       |
//+------------------------------------------------------------------+
void CreateClockLabel(string name, int x, int y, int width, int height)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        height);
   ObjectSetString (0, name, OBJPROP_TEXT,         "--:-- --");
   ObjectSetString (0, name, OBJPROP_FONT,         FONT_NAME);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,     FONT_SIZE_LABEL);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      clrSteelBlue);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrSteelBlue);
   ObjectSetInteger(0, name, OBJPROP_STATE,        true);    // visually static (always "pressed")
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
}

//+------------------------------------------------------------------+
//| Create a standard action button on the top row.                  |
//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, string text, color clr)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     BTN_WIDTH);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     BTN_HEIGHT);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   clr);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clrWhite);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Create a bold label aligned to a panel row.                      |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y + LABEL_Y_OFFSET);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetString (0, name, OBJPROP_FONT,      FONT_NAME);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clrBlack);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  FONT_SIZE_LABEL);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Create an editable text field aligned to a panel row.            |
//+------------------------------------------------------------------+
void CreateEditField(string name, int x, int y, int width, string defaultText)
{
   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     EDIT_HEIGHT);
   ObjectSetString (0, name, OBJPROP_TEXT,      defaultText);
   ObjectSetString (0, name, OBJPROP_FONT,      FONT_NAME);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  FONT_SIZE_EDIT);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   clrWhiteSmoke);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clrBlack);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//==================================================================
//  CLEANUP
//==================================================================

//+------------------------------------------------------------------+
//| Delete every UI object created by this EA.                       |
//+------------------------------------------------------------------+
void DeleteAllUIObjects()
{
   // Preset buttons (dynamic count)
   for(int i = 0; i < PRESET_COUNT; i++)
      ObjectDelete(0, PRESET_BTN_PREFIX + IntegerToString(i));

   // Trade panel: header cells, data cells, checkboxes, and grid lines
   for(int i = 0; i < TRADE_COLS; i++)
      ObjectDelete(0, TRADE_HDR_PREFIX + IntegerToString(i));
   for(int r = 0; r < TRADE_MAX_ROWS; r++)
   {
      string rp = TRADE_CELL_PREFIX + IntegerToString(r) + "_";
      for(int c = 0; c < TRADE_COLS; c++)
         ObjectDelete(0, rp + IntegerToString(c));
      ObjectDelete(0, TRADE_CHK_PREFIX + IntegerToString(r));
   }
   ObjectDelete(0, TRADE_CHK_ALL);
   for(int i = 0; i < gGridCount; i++)
      ObjectDelete(0, TRADE_GRID_PREFIX + IntegerToString(i));

   // Static UI objects
   string names[] = {
      BTN_BUY, BTN_SELL, BTN_CLOSE_PROFIT, BTN_CLOSE_LOSS, BTN_CLOSE_ALL,
      BTN_THEME, BTN_CLEAR_SL, BTN_REMOVE_SL, BTN_CLOSE_SELECTED,
      EDIT_LOT, LABEL_LOT,
      EDIT_NEWSL, LABEL_NEWSL,
      EDIT_NEWTP, LABEL_NEWTP,
      LABEL_CLOCK,
      PANEL_BG, PRICE_PANEL_BG, PRICE_LABEL, PNL_LABEL,
      TRADE_PANEL_BG
   };
   for(int i = 0; i < ArraySize(names); i++)
      ObjectDelete(0, names[i]);
}
