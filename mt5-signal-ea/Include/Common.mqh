//+------------------------------------------------------------------+
//| Common.mqh - kiểu dữ liệu chung, log, tiện ích chuỗi/thời gian    |
//| Không tham chiếu input -> được include TRƯỚC khai báo input.      |
//+------------------------------------------------------------------+
#ifndef SIGNALEA_COMMON_MQH
#define SIGNALEA_COMMON_MQH

#define EA_NAME       "SignalEA"
#define EA_VERSION    "0.1.0"
#define EA_STAGE      "Giai đoạn 1"
#define EA_FILES_DIR  "SignalEA"

//--- Chế độ vũ trụ quét
enum ENUM_UNIVERSE_MODE
  {
   WATCHLIST_ONLY=0,       // Chỉ danh sách ưu tiên + phụ
   MARKET_WATCH=1,         // Ưu tiên + phụ + symbol đang có trong Market Watch
   ALL_BROKER_SYMBOLS=2    // Ưu tiên + phụ + mọi symbol đủ điều kiện của broker
  };

//--- Nhóm tài sản
enum ENUM_ASSET_GROUP
  {
   AG_FOREX=0,
   AG_METALS=1,
   AG_CRYPTO=2,
   AG_INDICES=3,
   AG_ENERGIES=4,
   AG_STOCKS=5,
   AG_OTHER=6
  };
#define AG_COUNT 7

//--- Tầng symbol
enum ENUM_SYMBOL_TIER
  {
   TIER_PRIORITY=0,   // Ưu tiên
   TIER_SECONDARY=1,  // Phụ
   TIER_DISCOVERY=2   // Khám phá
  };

//--- Mức log
enum ENUM_LOG_LEVEL
  {
   LOGLVL_ERROR=0,  // Chỉ lỗi
   LOGLVL_WARN=1,   // Lỗi + cảnh báo
   LOGLVL_INFO=2,   // Thông tin (khuyên dùng)
   LOGLVL_DEBUG=3   // Chi tiết (kiểm thử)
  };

//--- Chỉ số khung thời gian dùng trong mảng snapshot
#define TFI_MN1   0
#define TFI_W1    1
#define TFI_D1    2
#define TFI_H4    3
#define TFI_H1    4
#define TFI_COUNT 5

ENUM_TIMEFRAMES g_tfList[TFI_COUNT]={PERIOD_MN1,PERIOD_W1,PERIOD_D1,PERIOD_H4,PERIOD_H1};

int g_logLevel=LOGLVL_INFO;

//+------------------------------------------------------------------+
//| Log                                                              |
//+------------------------------------------------------------------+
void LogE(const string msg) { Print("[LỖI] ",msg); }
void LogW(const string msg) { if(g_logLevel>=LOGLVL_WARN)  Print("[CẢNH BÁO] ",msg); }
void LogI(const string msg) { if(g_logLevel>=LOGLVL_INFO)  Print(msg); }
void LogD(const string msg) { if(g_logLevel>=LOGLVL_DEBUG) Print("[DEBUG] ",msg); }

//+------------------------------------------------------------------+
//| Tên hiển thị                                                     |
//+------------------------------------------------------------------+
string GroupName(const ENUM_ASSET_GROUP g)
  {
   switch(g)
     {
      case AG_FOREX:    return "Forex";
      case AG_METALS:   return "Kim loại";
      case AG_CRYPTO:   return "Crypto";
      case AG_INDICES:  return "Chỉ số";
      case AG_ENERGIES: return "Năng lượng";
      case AG_STOCKS:   return "Cổ phiếu";
      default:          return "Khác";
     }
  }

string TierName(const ENUM_SYMBOL_TIER t)
  {
   switch(t)
     {
      case TIER_PRIORITY:  return "Ưu tiên";
      case TIER_SECONDARY: return "Phụ";
      default:             return "Khám phá";
     }
  }

string TfName(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_MN1: return "MN1";
      case PERIOD_W1:  return "W1";
      case PERIOD_D1:  return "D1";
      case PERIOD_H4:  return "H4";
      case PERIOD_H1:  return "H1";
      default:         return EnumToString(tf);
     }
  }

//+------------------------------------------------------------------+
//| Tiện ích chuỗi                                                   |
//+------------------------------------------------------------------+
string StrTrim(string s)
  {
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
  }

string StrUpper(string s)
  {
   StringToUpper(s);
   return s;
  }

string StrLower(string s)
  {
   StringToLower(s);
   return s;
  }

bool StrContains(const string s,const string sub)
  {
   return (StringFind(s,sub)>=0);
  }

bool StrEndsWith(const string s,const string suffix)
  {
   int ls=StringLen(s);
   int lf=StringLen(suffix);
   if(lf==0)
      return true;
   if(lf>ls)
      return false;
   return (StringSubstr(s,ls-lf,lf)==suffix);
  }

bool StrStartsWith(const string s,const string prefix)
  {
   int lp=StringLen(prefix);
   if(lp==0)
      return true;
   return (StringSubstr(s,0,lp)==prefix);
  }

// Tách danh sách "A, B; C" thành mảng (bỏ phần tử rỗng)
int SplitCsv(const string csv,string &out[])
  {
   ArrayResize(out,0);
   string tmp=csv;
   StringReplace(tmp,";",",");
   string parts[];
   int n=StringSplit(tmp,',',parts);
   int cnt=0;
   for(int i=0;i<n;i++)
     {
      string p=StrTrim(parts[i]);
      if(p=="")
         continue;
      ArrayResize(out,cnt+1);
      out[cnt]=p;
      cnt++;
     }
   return cnt;
  }

bool StrInArray(const string s,const string &arr[])
  {
   int n=ArraySize(arr);
   for(int i=0;i<n;i++)
      if(arr[i]==s)
         return true;
   return false;
  }

void StrArrayPush(string &arr[],const string s)
  {
   int n=ArraySize(arr);
   ArrayResize(arr,n+1);
   arr[n]=s;
  }

//+------------------------------------------------------------------+
//| Thời gian: server -> múi giờ hiển thị                            |
//+------------------------------------------------------------------+
int    g_serverGmtOffsetSec=0;     // giờ server - GMT
int    g_displayOffsetSec=7*3600;  // múi giờ hiển thị so với GMT
string g_displayTzLabel="GMT+7";

void TimeInitOffsets(const double displayGmtHours)
  {
   long diff=(long)TimeTradeServer()-(long)TimeGMT();
   // làm tròn tới 15 phút để tránh lệch vài giây
   g_serverGmtOffsetSec=(int)(MathRound((double)diff/900.0)*900.0);
   g_displayOffsetSec=(int)MathRound(displayGmtHours*3600.0);
   string sign=(displayGmtHours>=0.0) ? "+" : "-";
   double a=MathAbs(displayGmtHours);
   if(MathAbs(a-MathRound(a))<0.001)
      g_displayTzLabel="GMT"+sign+IntegerToString((int)MathRound(a));
   else
      g_displayTzLabel="GMT"+sign+DoubleToString(a,1);
  }

datetime ServerToDisplay(const datetime serverTime)
  {
   return (datetime)((long)serverTime-g_serverGmtOffsetSec+g_displayOffsetSec);
  }

// "14/10 13:55 (GMT+7)"
string FmtDisplayTime(const datetime serverTime)
  {
   MqlDateTime dt;
   TimeToStruct(ServerToDisplay(serverTime),dt);
   return StringFormat("%02d/%02d %02d:%02d (%s)",dt.day,dt.mon,dt.hour,dt.min,g_displayTzLabel);
  }

// Đầu giờ server hiện tại (khóa "giờ" cho vòng quét)
datetime HourKey(const datetime t)
  {
   long v=(long)t;
   return (datetime)(v-(v%3600));
  }

//+------------------------------------------------------------------+
//| Định dạng số                                                     |
//+------------------------------------------------------------------+
string FmtPrice(const string sym,const double price)
  {
   if(price==EMPTY_VALUE)
      return "n/a";
   int digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   return DoubleToString(price,digits);
  }

string FmtMoney(const double v)
  {
   string ccy=AccountInfoString(ACCOUNT_CURRENCY);
   int dec=(MathAbs(v)>=100.0) ? 0 : 2;
   if(ccy=="USD" || ccy=="")
      return "$"+DoubleToString(v,dec);
   return DoubleToString(v,dec)+" "+ccy;
  }

string FmtVal(const double v,const int dec)
  {
   if(v==EMPTY_VALUE || !MathIsValidNumber(v))
      return "n/a";
   return DoubleToString(v,dec);
  }

#endif
