//+------------------------------------------------------------------+
//| Universe.mqh - khám phá, phân loại, lọc symbol, quét xoay vòng   |
//| Include SAU khai báo input (dùng trực tiếp các biến Inp*).        |
//+------------------------------------------------------------------+
#ifndef SIGNALEA_UNIVERSE_MQH
#define SIGNALEA_UNIVERSE_MQH

#include "Common.mqh"

//--- Mã trạng thái xử lý (chỉ log khi đổi trạng thái để tránh spam log)
#define SST_NEW             0
#define SST_OK              1
#define SST_SESSION_CLOSED  2
#define SST_MW_FULL         3
#define SST_WAIT_QUOTE      4
#define SST_STALE_QUOTE     5
#define SST_BAD_SPEC        6
#define SST_HISTORY_LOADING 7
#define SST_HISTORY_MISSING 8
#define SST_SPREAD_WIDE     9
#define SST_CAPITAL         10
#define SST_ERROR           11
#define SST_COUNT           12

struct SymbolRec
  {
   string            name;          // tên đầy đủ trên broker (có hậu tố)
   string            base;          // tên đã bỏ hậu tố
   ENUM_ASSET_GROUP  assetGroup;
   ENUM_SYMBOL_TIER  tier;
   bool              selectedByEA;  // EA đã tự thêm vào Market Watch
   datetime          selectedAt;
   //--- runtime
   datetime          lastHourKey;   // giờ server đã xử lý xong
   datetime          lastClosedH1;  // nến H1 đã đóng đã phân tích
   int               deferCount;    // số lần hoãn trong giờ hiện tại
   int               status;
   string            statusText;
   datetime          lastAnalyzed;
   double            spreadAtrPct;
   double            rsiH1;
   double            closeH1;
   double            minLotRiskPct;
  };

SymbolRec g_uni[];
int       g_rrPtr=0;                // con trỏ quét xoay vòng
int       g_uniRejectedCount=0;
datetime  g_uniBuiltAt=0;
string    g_foreignSuffixes[];

//--- Gom lý do loại (static) để log gọn
string g_rejReasons[];
string g_rejNames[];
int    g_rejCounts[];

string StatusName(const int code)
  {
   switch(code)
     {
      case SST_NEW:             return "mới";
      case SST_OK:              return "OK";
      case SST_SESSION_CLOSED:  return "ngoài phiên";
      case SST_MW_FULL:         return "Market Watch đầy";
      case SST_WAIT_QUOTE:      return "chờ báo giá";
      case SST_STALE_QUOTE:     return "báo giá cũ";
      case SST_BAD_SPEC:        return "spec bất thường";
      case SST_HISTORY_LOADING: return "đang tải lịch sử";
      case SST_HISTORY_MISSING: return "thiếu lịch sử";
      case SST_SPREAD_WIDE:     return "spread rộng";
      case SST_CAPITAL:         return "vượt khả năng vốn";
      default:                  return "lỗi";
     }
  }

void UniInitRec(SymbolRec &r,const string name,const string base,const ENUM_ASSET_GROUP g,const ENUM_SYMBOL_TIER t)
  {
   r.name=name;
   r.base=base;
   r.assetGroup=g;
   r.tier=t;
   r.selectedByEA=false;
   r.selectedAt=0;
   r.lastHourKey=0;
   r.lastClosedH1=0;
   r.deferCount=0;
   r.status=SST_NEW;
   r.statusText="";
   r.lastAnalyzed=0;
   r.spreadAtrPct=EMPTY_VALUE;
   r.rsiH1=EMPTY_VALUE;
   r.closeH1=EMPTY_VALUE;
   r.minLotRiskPct=EMPTY_VALUE;
  }

// Copy từng trường (tránh phụ thuộc vào phép gán struct có string)
void UniCopyRec(SymbolRec &d,const SymbolRec &s)
  {
   d.name=s.name;
   d.base=s.base;
   d.assetGroup=s.assetGroup;
   d.tier=s.tier;
   d.selectedByEA=s.selectedByEA;
   d.selectedAt=s.selectedAt;
   d.lastHourKey=s.lastHourKey;
   d.lastClosedH1=s.lastClosedH1;
   d.deferCount=s.deferCount;
   d.status=s.status;
   d.statusText=s.statusText;
   d.lastAnalyzed=s.lastAnalyzed;
   d.spreadAtrPct=s.spreadAtrPct;
   d.rsiH1=s.rsiH1;
   d.closeH1=s.closeH1;
   d.minLotRiskPct=s.minLotRiskPct;
  }

// Chỉ copy phần runtime (khi dựng lại universe)
void UniCopyRuntime(SymbolRec &d,const SymbolRec &s)
  {
   d.selectedByEA=s.selectedByEA;
   d.selectedAt=s.selectedAt;
   d.lastHourKey=s.lastHourKey;
   d.lastClosedH1=s.lastClosedH1;
   d.deferCount=s.deferCount;
   d.status=s.status;
   d.statusText=s.statusText;
   d.lastAnalyzed=s.lastAnalyzed;
   d.spreadAtrPct=s.spreadAtrPct;
   d.rsiH1=s.rsiH1;
   d.closeH1=s.closeH1;
   d.minLotRiskPct=s.minLotRiskPct;
  }

int UniFindIn(const SymbolRec &arr[],const string name)
  {
   int n=ArraySize(arr);
   for(int i=0;i<n;i++)
      if(arr[i].name==name)
         return i;
   return -1;
  }

int UniFind(const string name)
  {
   return UniFindIn(g_uni,name);
  }

void UniPush(SymbolRec &arr[],const string name,const string base,const ENUM_ASSET_GROUP g,const ENUM_SYMBOL_TIER t)
  {
   int n=ArraySize(arr);
   ArrayResize(arr,n+1,64);
   UniInitRec(arr[n],name,base,g,t);
  }

//+------------------------------------------------------------------+
//| Phân loại nhóm tài sản                                           |
//+------------------------------------------------------------------+
bool UniStartsWithAny(const string up,const string &codes[])
  {
   int n=ArraySize(codes);
   for(int i=0;i<n;i++)
      if(StrStartsWith(up,codes[i]))
         return true;
   return false;
  }

bool UniContainsAny(const string up,const string &codes[])
  {
   int n=ArraySize(codes);
   for(int i=0;i<n;i++)
      if(StrContains(up,codes[i]))
         return true;
   return false;
  }

ENUM_ASSET_GROUP UniClassify(const string sym)
  {
   string metals[]={"XAU","XAG","XPT","XPD"};
   string cryptos[]={"BTC","ETH","LTC","XRP","BCH","ADA","DOT","SOL","DOGE","BNB","LINK","UNI","XLM",
                     "AVAX","MATIC","POL","TRX","ATOM","XTZ","EOS","FIL","AAVE","SHIB","TON","NEAR","ARB","OP"};
   string energies[]={"OIL","BRENT","WTI","NGAS","XNG","XTI","XBR","GASOIL"};
   string indices[]={"US30","US500","USTEC","US100","US2000","NAS100","SPX","DJ30","DE30","DE40","GER",
                     "UK100","FR40","JP225","HK50","AUS200","STOXX50","EU50","CN50","ES35","IT40","IN50"};

   string path=StrLower(SymbolInfoString(sym,SYMBOL_PATH));
   string up=StrUpper(sym);
   string baseCcy=StrUpper(SymbolInfoString(sym,SYMBOL_CURRENCY_BASE));
   ENUM_ASSET_GROUP g=AG_OTHER;

   //--- 1) theo SYMBOL_PATH
   if(StrContains(path,"crypto"))
      g=AG_CRYPTO;
   else if(StrContains(path,"metal"))
      g=AG_METALS;
   else if(StrContains(path,"energ") || StrContains(path,"oil"))
      g=AG_ENERGIES;
   else if(StrContains(path,"indic") || StrContains(path,"index") || StrContains(path,"indices"))
      g=AG_INDICES;
   else if(StrContains(path,"stock") || StrContains(path,"share") || StrContains(path,"equit"))
      g=AG_STOCKS;
   else if(StrContains(path,"forex") || StrContains(path,"currenc") || StrContains(path,"major") ||
           StrContains(path,"minor") || StrContains(path,"exotic") || StrStartsWith(path,"fx"))
      g=AG_FOREX;

   //--- 2) chỉnh theo tên / tiền tệ cơ sở (ví dụ XAUUSD nằm trong thư mục Forex)
   if(g==AG_FOREX || g==AG_OTHER)
     {
      if(UniStartsWithAny(baseCcy,metals) || UniStartsWithAny(up,metals))
         g=AG_METALS;
      else if(UniStartsWithAny(baseCcy,cryptos) || (g==AG_OTHER && UniStartsWithAny(up,cryptos)))
         g=AG_CRYPTO;
      else if(UniContainsAny(up,energies))
         g=AG_ENERGIES;
     }

   //--- 3) dự phòng theo kiểu tính margin
   if(g==AG_OTHER)
     {
      ENUM_SYMBOL_CALC_MODE cm=(ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(sym,SYMBOL_TRADE_CALC_MODE);
      if(cm==SYMBOL_CALC_MODE_FOREX || cm==SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE)
         g=AG_FOREX;
      else if(cm==SYMBOL_CALC_MODE_CFDINDEX || UniStartsWithAny(up,indices))
         g=AG_INDICES;
      else if(cm==SYMBOL_CALC_MODE_EXCH_STOCKS)
         g=AG_STOCKS;
     }
   return g;
  }

bool UniGroupEnabled(const ENUM_ASSET_GROUP g)
  {
   switch(g)
     {
      case AG_FOREX:    return InpEnableForex;
      case AG_METALS:   return InpEnableMetals;
      case AG_CRYPTO:   return InpEnableCrypto;
      case AG_INDICES:  return InpEnableIndices;
      case AG_ENERGIES: return InpEnableEnergies;
      case AG_STOCKS:   return InpEnableStocks;
      default:          return InpEnableOther;
     }
  }

//+------------------------------------------------------------------+
//| Hậu tố                                                           |
//+------------------------------------------------------------------+
// Tên đầy đủ từ tên gốc người dùng nhập (tự thêm hậu tố nếu thiếu)
string UniResolveName(const string userName)
  {
   string s=StrTrim(userName);
   if(InpSymbolSuffix!="" && !StrEndsWith(s,InpSymbolSuffix))
      s=s+InpSymbolSuffix;
   return s;
  }

bool UniSuffixOk(const string sym,string &base,string &reason)
  {
   base=sym;
   reason="";
   string sfx=InpSymbolSuffix;
   if(sfx!="")
     {
      if(StringLen(sym)<=StringLen(sfx) || !StrEndsWith(sym,sfx))
        {
         reason="không khớp hậu tố '"+sfx+"'";
         return false;
        }
      base=StringSubstr(sym,0,StringLen(sym)-StringLen(sfx));
      return true;
     }
   // Không hậu tố (tài khoản Pro): loại biến thể của loại tài khoản khác, ví dụ XAUUSDm, XAUUSDc
   int n=ArraySize(g_foreignSuffixes);
   for(int i=0;i<n;i++)
     {
      string f=g_foreignSuffixes[i];
      if(StringLen(sym)>StringLen(f) && StrEndsWith(sym,f))
        {
         string b=StringSubstr(sym,0,StringLen(sym)-StringLen(f));
         if(b==StrUpper(b))
           {
            reason="hậu tố khác '"+f+"'";
            return false;
           }
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Gom lý do loại                                                   |
//+------------------------------------------------------------------+
void UniRejReset()
  {
   ArrayResize(g_rejReasons,0);
   ArrayResize(g_rejNames,0);
   ArrayResize(g_rejCounts,0);
  }

void UniRejAdd(const string sym,const string reason)
  {
   int n=ArraySize(g_rejReasons);
   for(int i=0;i<n;i++)
     {
      if(g_rejReasons[i]==reason)
        {
         g_rejNames[i]+=", "+sym;
         g_rejCounts[i]++;
         return;
        }
     }
   ArrayResize(g_rejReasons,n+1);
   ArrayResize(g_rejNames,n+1);
   ArrayResize(g_rejCounts,n+1);
   g_rejReasons[n]=reason;
   g_rejNames[n]=sym;
   g_rejCounts[n]=1;
  }

// In một danh sách dài thành nhiều dòng (tránh dòng log quá dài)
void UniPrintLongList(const string header,const string list)
  {
   const int chunk=900;
   int len=StringLen(list);
   if(len<=chunk)
     {
      LogI(header+list);
      return;
     }
   int pos=0;
   int part=1;
   while(pos<len)
     {
      int take=MathMin(chunk,len-pos);
      // cắt tại dấu phẩy gần nhất
      if(pos+take<len)
        {
         int cut=take;
         while(cut>0 && StringGetCharacter(list,pos+cut-1)!=',')
            cut--;
         if(cut>0)
            take=cut;
        }
      LogI(StringFormat("%s(phần %d) %s",header,part,StrTrim(StringSubstr(list,pos,take))));
      pos+=take;
      part++;
     }
  }

//+------------------------------------------------------------------+
//| Kiểm tra tĩnh: chế độ giao dịch                                  |
//+------------------------------------------------------------------+
bool UniTradeModeOk(const string sym,string &reason)
  {
   ENUM_SYMBOL_TRADE_MODE tm=(ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(sym,SYMBOL_TRADE_MODE);
   if(tm==SYMBOL_TRADE_MODE_FULL)
      return true;
   reason="không cho phép giao dịch đầy đủ ("+EnumToString(tm)+")";
   return false;
  }

//+------------------------------------------------------------------+
//| Dựng danh sách symbol                                            |
//+------------------------------------------------------------------+
void UniWriteReport(const SymbolRec &acc[])
  {
   string fname=EA_FILES_DIR+"\\universe.csv";
   int h=FileOpen(fname,FILE_WRITE|FILE_CSV|FILE_UNICODE|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE)
     {
      LogW(StringFormat("Không ghi được %s (lỗi %d)",fname,GetLastError()));
      return;
     }
   FileWrite(h,"symbol","ket_qua","tang_hoac_ly_do","nhom","path");
   int n=ArraySize(acc);
   for(int i=0;i<n;i++)
      FileWrite(h,acc[i].name,"NHAN",TierName(acc[i].tier),GroupName(acc[i].assetGroup),
                SymbolInfoString(acc[i].name,SYMBOL_PATH));
   int m=ArraySize(g_rejReasons);
   for(int k=0;k<m;k++)
     {
      string names[];
      int cnt=StringSplit(g_rejNames[k],',',names);
      for(int j=0;j<cnt;j++)
        {
         string s=StrTrim(names[j]);
         FileWrite(h,s,"LOAI",g_rejReasons[k],"",SymbolInfoString(s,SYMBOL_PATH));
        }
     }
   FileClose(h);
   LogI("Chi tiết danh sách nhận/loại: MQL5\\Files\\"+fname);
  }

void UniAddWatchlist(SymbolRec &arr[],const string csv,const ENUM_SYMBOL_TIER tier)
  {
   string items[];
   int n=SplitCsv(csv,items);
   for(int i=0;i<n;i++)
     {
      string full=UniResolveName(items[i]);
      bool isCustom=false;
      if(!SymbolExist(full,isCustom))
        {
         LogE(StringFormat("Symbol %s '%s' không tồn tại trên broker - bỏ qua. Kiểm tra tên/hậu tố.",
                           TierName(tier),full));
         UniRejAdd(full,"không tồn tại trên broker");
         continue;
        }
      if(UniFindIn(arr,full)>=0)
         continue;
      string reason="";
      if(!UniTradeModeOk(full,reason))
        {
         LogW(StringFormat("Symbol %s %s: %s - bỏ qua.",TierName(tier),full,reason));
         UniRejAdd(full,reason);
         continue;
        }
      string base=full;
      if(InpSymbolSuffix!="" && StrEndsWith(full,InpSymbolSuffix))
         base=StringSubstr(full,0,StringLen(full)-StringLen(InpSymbolSuffix));
      UniPush(arr,full,base,UniClassify(full),tier);
     }
  }

bool UniBuild()
  {
   ulong t0=GetTickCount64();
   SplitCsv(InpForeignSuffixes,g_foreignSuffixes);
   string excludes[];
   SplitCsv(InpExcludeSymbols,excludes);
   UniRejReset();

   SymbolRec nu[];
   UniAddWatchlist(nu,InpPrioritySymbols,TIER_PRIORITY);
   UniAddWatchlist(nu,InpSecondarySymbols,TIER_SECONDARY);

   //--- ứng viên khám phá
   int total=0;
   bool fromMarketWatch=(InpUniverseMode==MARKET_WATCH);
   if(InpUniverseMode!=WATCHLIST_ONLY)
      total=SymbolsTotal(fromMarketWatch);
   for(int i=0;i<total;i++)
     {
      string sym=SymbolName(i,fromMarketWatch);
      if(sym=="" || UniFindIn(nu,sym)>=0)
         continue;
      if(StrInArray(sym,excludes))
        {
         UniRejAdd(sym,"nằm trong danh sách loại trừ");
         continue;
        }
      if((bool)SymbolInfoInteger(sym,SYMBOL_CUSTOM))
        {
         UniRejAdd(sym,"symbol tùy chỉnh");
         continue;
        }
      string base="",reason="";
      if(!UniSuffixOk(sym,base,reason))
        {
         UniRejAdd(sym,reason);
         continue;
        }
      ENUM_ASSET_GROUP g=UniClassify(sym);
      if(!UniGroupEnabled(g))
        {
         UniRejAdd(sym,"nhóm "+GroupName(g)+" đang tắt");
         continue;
        }
      if(!UniTradeModeOk(sym,reason))
        {
         UniRejAdd(sym,reason);
         continue;
        }
      UniPush(nu,sym,base,g,TIER_DISCOVERY);
     }

   //--- giữ trạng thái runtime cũ; nhả symbol EA đã chọn mà không còn trong danh sách
   int nNew=ArraySize(nu);
   for(int i=0;i<nNew;i++)
     {
      int old=UniFind(nu[i].name);
      if(old>=0)
         UniCopyRuntime(nu[i],g_uni[old]);
     }
   int nOld=ArraySize(g_uni);
   for(int i=0;i<nOld;i++)
      if(g_uni[i].selectedByEA && UniFindIn(nu,g_uni[i].name)<0)
         SymbolSelect(g_uni[i].name,false);

   ArrayResize(g_uni,nNew);
   for(int i=0;i<nNew;i++)
      UniCopyRec(g_uni[i],nu[i]);
   if(g_rrPtr>=nNew)
      g_rrPtr=0;

   //--- log tổng kết
   g_uniRejectedCount=0;
   int m=ArraySize(g_rejCounts);
   for(int k=0;k<m;k++)
      g_uniRejectedCount+=g_rejCounts[k];
   g_uniBuiltAt=TimeTradeServer();

   LogI(StringFormat("=== Universe: chế độ %s | nhận %d | loại %d | duyệt %d symbol trong %I64u ms ===",
                     EnumToString(InpUniverseMode),nNew,g_uniRejectedCount,total,GetTickCount64()-t0));
   for(int gi=0;gi<AG_COUNT;gi++)
     {
      string list="";
      int cnt=0;
      for(int i=0;i<nNew;i++)
        {
         if((int)g_uni[i].assetGroup!=gi)
            continue;
         list+=(cnt>0 ? ", " : "")+g_uni[i].name;
         if(g_uni[i].tier!=TIER_DISCOVERY)
            list+="("+TierName(g_uni[i].tier)+")";
         cnt++;
        }
      if(cnt>0)
         UniPrintLongList(StringFormat("Nhận - %s (%d): ",GroupName((ENUM_ASSET_GROUP)gi),cnt),list);
     }
   for(int k=0;k<m;k++)
      UniPrintLongList(StringFormat("Loại - %s (%d): ",g_rejReasons[k],g_rejCounts[k]),g_rejNames[k]);
   UniWriteReport(g_uni);
   return (nNew>0);
  }

//+------------------------------------------------------------------+
//| Kiểm tra động (mỗi lần xử lý)                                    |
//+------------------------------------------------------------------+
bool UniIsInTradeSession(const string sym,const datetime now)
  {
   MqlDateTime dt;
   TimeToStruct(now,dt);
   long sec=dt.hour*3600+dt.min*60+dt.sec;
   datetime from=0,to=0;
   for(uint k=0;k<16;k++)
     {
      if(!SymbolInfoSessionTrade(sym,(ENUM_DAY_OF_WEEK)dt.day_of_week,k,from,to))
         break;
      long f=((long)from)%86400;
      long t=((long)to)%86400;
      if(t<=f)
         t+=86400;
      if(sec>=f && sec<t)
         return true;
     }
   return false;
  }

int UniMarketWatchCount()
  {
   return SymbolsTotal(true);
  }

void UniSetStatus(const int idx,const int code,const string text)
  {
   bool changed=(g_uni[idx].status!=code);
   g_uni[idx].status=code;
   g_uni[idx].statusText=text;
   if(!changed)
      return;
   string sym=g_uni[idx].name;
   string tag=StringFormat("[%s|%s] ",sym,TierName(g_uni[idx].tier));
   switch(code)
     {
      case SST_OK:
         if(g_uni[idx].tier==TIER_DISCOVERY)
            LogD(tag+"đủ điều kiện: "+text);
         else
            LogI(tag+"đủ điều kiện: "+text);
         break;
      case SST_SESSION_CLOSED:
      case SST_WAIT_QUOTE:
      case SST_HISTORY_LOADING:
         LogD(tag+text);
         break;
      case SST_ERROR:
         LogE(tag+text);
         break;
      default:
         LogI(tag+"loại lượt này: "+text);
     }
  }

// Đảm bảo symbol có trong Market Watch (cần để có báo giá/tick value)
bool UniEnsureSelected(const int idx)
  {
   string sym=g_uni[idx].name;
   if((bool)SymbolInfoInteger(sym,SYMBOL_SELECT))
      return true;
   if(g_uni[idx].tier==TIER_DISCOVERY && UniMarketWatchCount()>=InpMaxMarketWatch)
     {
      UniSetStatus(idx,SST_MW_FULL,StringFormat("Market Watch đã đầy (%d/%d)",UniMarketWatchCount(),InpMaxMarketWatch));
      return false;
     }
   ResetLastError();
   if(!SymbolSelect(sym,true))
     {
      UniSetStatus(idx,SST_ERROR,StringFormat("SymbolSelect lỗi %d",GetLastError()));
      return false;
     }
   g_uni[idx].selectedByEA=true;
   g_uni[idx].selectedAt=TimeTradeServer();
   return true;
  }

// 0 = có báo giá mới, 1 = đang chờ báo giá, 2 = báo giá quá cũ (nghỉ lễ/không thanh khoản)
int UniCheckQuote(const int idx,const datetime now)
  {
   string sym=g_uni[idx].name;
   double bid=SymbolInfoDouble(sym,SYMBOL_BID);
   double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
   datetime qt=(datetime)SymbolInfoInteger(sym,SYMBOL_TIME);
   bool justSelected=(g_uni[idx].selectedByEA && (long)now-(long)g_uni[idx].selectedAt<180);
   if(bid<=0.0 || ask<=0.0 || qt==0)
      return 1;
   if((long)now-(long)qt>(long)InpMaxQuoteAgeMin*60)
      return justSelected ? 1 : 2;
   return 0;
  }

void UniReleaseIfOwned(const int idx)
  {
   if(!InpReleaseSymbolsAfterScan || !g_uni[idx].selectedByEA || g_uni[idx].tier!=TIER_DISCOVERY)
      return;
   if(SymbolSelect(g_uni[idx].name,false))
      g_uni[idx].selectedByEA=false;
  }

void UniReleaseAllOwned()
  {
   int n=ArraySize(g_uni);
   int cnt=0;
   for(int i=0;i<n;i++)
     {
      if(!g_uni[i].selectedByEA)
         continue;
      if(SymbolSelect(g_uni[i].name,false))
        {
         g_uni[i].selectedByEA=false;
         cnt++;
        }
     }
   if(cnt>0)
      LogI(StringFormat("Đã gỡ %d symbol do EA thêm khỏi Market Watch.",cnt));
  }

bool UniIsDue(const int idx,const datetime hourKey)
  {
   return (g_uni[idx].lastHourKey!=hourKey);
  }

#endif
