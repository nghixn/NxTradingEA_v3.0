//+------------------------------------------------------------------+
//|                                               ExportHistory.mq5  |
//| Script xuất lịch sử nến + thông số hợp đồng cho backtest Python. |
//| Ghi vào MQL5/Files/SignalEA/history/:                            |
//|   <SYM>_<TF>.csv : time;open;high;low;close;spread (time = giờ   |
//|                    server, giây Unix; spread tính theo point)    |
//|   <SYM>_spec.csv : key;value (tick size, tick value, lot...)     |
//| Chỉ đọc dữ liệu, KHÔNG giao dịch.                                |
//+------------------------------------------------------------------+
#property copyright   "NxTrading"
#property version     "1.00"
#property description "Xuất lịch sử MN1/W1/D1/H4/H1/M1 + spec cho backtest SignalEA"
#property script_show_inputs

input string InpSymbols   = "BTCUSD,XAUUSD,ETHUSD,XAGUSD,EURUSD,GBPUSD,USDJPY,US30"; // Danh sách symbol
input string InpSuffix    = "";      // Hậu tố symbol (Exness Pro: để trống)
input int    InpYears     = 3;       // Số năm lịch sử cho H1 trở lên
input int    InpM1Days    = 180;     // Số ngày nến M1 (0 = không xuất M1)

string g_dir="SignalEA\\history\\";

string TfCode(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_MN1: return "MN1";
      case PERIOD_W1:  return "W1";
      case PERIOD_D1:  return "D1";
      case PERIOD_H4:  return "H4";
      case PERIOD_H1:  return "H1";
      default:         return "M1";
     }
  }

bool WriteText(const string fname,const string text)
  {
   uchar bytes[];
   int n=StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8);
   if(n>0 && bytes[n-1]==0)
      n--;
   int h=FileOpen(fname,FILE_WRITE|FILE_BIN);
   if(h==INVALID_HANDLE)
     {
      Print("[EXPORT] Không ghi được ",fname," lỗi ",GetLastError());
      return false;
     }
   FileWriteArray(h,bytes,0,n);
   FileClose(h);
   return true;
  }

int ExportSeries(const string sym,const ENUM_TIMEFRAMES tf,const datetime from)
  {
   MqlRates r[];
   datetime to=TimeTradeServer();
   int n=0;
   // CopyRates có thể trả thiếu khi lịch sử đang tải: thử vài lần
   for(int attempt=0;attempt<5;attempt++)
     {
      ResetLastError();
      n=CopyRates(sym,tf,from,to,r);
      if(n>0)
         break;
      Sleep(1000);
     }
   if(n<=0)
     {
      Print("[EXPORT] ",sym," ",TfCode(tf),": không lấy được dữ liệu (lỗi ",GetLastError(),")");
      return 0;
     }
   int dg=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   string fname=g_dir+sym+"_"+TfCode(tf)+".csv";
   int h=FileOpen(fname,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
     {
      Print("[EXPORT] Không ghi được ",fname," lỗi ",GetLastError());
      return 0;
     }
   FileWriteString(h,"time;open;high;low;close;spread\r\n");
   // bỏ nến cuối (đang chạy)
   for(int i=0;i<n-1;i++)
      FileWriteString(h,IntegerToString((long)r[i].time)+";"+DoubleToString(r[i].open,dg)+";"+
                      DoubleToString(r[i].high,dg)+";"+DoubleToString(r[i].low,dg)+";"+
                      DoubleToString(r[i].close,dg)+";"+IntegerToString(r[i].spread)+"\r\n");
   FileClose(h);
   return n-1;
  }

void ExportSpec(const string sym)
  {
   string t="key;value\r\n";
   t+="symbol;"+sym+"\r\n";
   t+="digits;"+IntegerToString(SymbolInfoInteger(sym,SYMBOL_DIGITS))+"\r\n";
   t+="point;"+DoubleToString(SymbolInfoDouble(sym,SYMBOL_POINT),10)+"\r\n";
   t+="tick_size;"+DoubleToString(SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE),10)+"\r\n";
   t+="tick_value;"+DoubleToString(SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE),10)+"\r\n";
   t+="tick_value_loss;"+DoubleToString(SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE_LOSS),10)+"\r\n";
   t+="contract_size;"+DoubleToString(SymbolInfoDouble(sym,SYMBOL_TRADE_CONTRACT_SIZE),10)+"\r\n";
   t+="volume_min;"+DoubleToString(SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN),10)+"\r\n";
   t+="volume_step;"+DoubleToString(SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP),10)+"\r\n";
   t+="volume_max;"+DoubleToString(SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX),10)+"\r\n";
   t+="currency_base;"+SymbolInfoString(sym,SYMBOL_CURRENCY_BASE)+"\r\n";
   t+="currency_profit;"+SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT)+"\r\n";
   t+="path;"+SymbolInfoString(sym,SYMBOL_PATH)+"\r\n";
   t+="calc_mode;"+EnumToString((ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(sym,SYMBOL_TRADE_CALC_MODE))+"\r\n";
   t+="account_currency;"+AccountInfoString(ACCOUNT_CURRENCY)+"\r\n";
   long offset=(long)TimeTradeServer()-(long)TimeGMT();
   t+="server_gmt_offset_sec;"+IntegerToString((long)(MathRound((double)offset/900.0)*900.0))+"\r\n";
   WriteText(g_dir+sym+"_spec.csv",t);
  }

void OnStart()
  {
   string items[];
   string csv=InpSymbols;
   StringReplace(csv,";",",");
   int n=StringSplit(csv,',',items);
   datetime now=TimeTradeServer();
   datetime fromHi=(datetime)((long)now-(long)InpYears*365*86400);
   datetime fromM1=(datetime)((long)now-(long)InpM1Days*86400);
   ENUM_TIMEFRAMES tfs[5]={PERIOD_MN1,PERIOD_W1,PERIOD_D1,PERIOD_H4,PERIOD_H1};
   Print("[EXPORT] Bắt đầu xuất ",n," symbol vào MQL5\\Files\\",g_dir);
   for(int i=0;i<n;i++)
     {
      string sym=items[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(sym=="")
         continue;
      if(InpSuffix!="" && StringFind(sym,InpSuffix)<0)
         sym+=InpSuffix;
      bool isCustom=false;
      if(!SymbolExist(sym,isCustom))
        {
         Print("[EXPORT] Symbol không tồn tại: ",sym);
         continue;
        }
      SymbolSelect(sym,true);
      ExportSpec(sym);
      string summary=sym+":";
      for(int t=0;t<5;t++)
        {
         // MN1/W1 lấy toàn bộ lịch sử có sẵn để đủ nến cho SMA200
         datetime from=(tfs[t]==PERIOD_MN1 || tfs[t]==PERIOD_W1) ? (datetime)0 : fromHi;
         int cnt=ExportSeries(sym,tfs[t],from);
         summary+=" "+TfCode(tfs[t])+"="+IntegerToString(cnt);
        }
      if(InpM1Days>0)
         summary+=" M1="+IntegerToString(ExportSeries(sym,PERIOD_M1,fromM1));
      Print("[EXPORT] ",summary);
     }
   Print("[EXPORT] Xong. Chép thư mục MQL5\\Files\\",g_dir," sang máy chạy Python nếu cần.");
  }
//+------------------------------------------------------------------+
