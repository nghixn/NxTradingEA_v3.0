//+------------------------------------------------------------------+
//| Signals.mqh - vòng đời setup, ưu tiên/tương quan/phơi nhiễm,     |
//| tổng rủi ro, xếp hạng top K, giới hạn tin/ngày, nội dung tin.    |
//| Include SAU khai báo input và sau Universe/Analysis/Risk/News.   |
//+------------------------------------------------------------------+
#ifndef SIGNALEA_SIGNALS_MQH
#define SIGNALEA_SIGNALS_MQH

#include "Common.mqh"
#include "Risk.mqh"
#include "Analysis.mqh"
#include "Universe.mqh"
#include "News.mqh"
#include "Telegram.mqh"

//--- Trạng thái setup
#define SS_ACTIVE       0   // chờ giá vào vùng Entry
#define SS_TRIGGERED    1   // giá đã vào vùng Entry
#define SS_PENDING_RISK 2   // đã báo "đang chờ, vượt ngưỡng rủi ro" (không tính rủi ro)
#define SS_INVALIDATED  3
#define SS_EXPIRED      4
#define SS_DONE         5   // đã chạm mục tiêu
#define SS_SKIPPED      6   // ứng viên bị loại (chỉ dùng trong vòng xếp hạng)

struct Setup
  {
   string            id;
   string            sym;
   string            corrGroup;
   string            baseCcy;
   string            quoteCcy;
   string            reasons;
   string            biasText;
   string            newsNote;
   int               tier;
   int               assetGroup;
   int               side;
   int               type;
   int               score;      // |bias|
   int               maxScore;
   int               confluence;
   int               state;
   double            entryLow;
   double            entryHigh;
   double            entryRef;
   double            sl;
   double            tp1;
   double            tp2;
   double            rr1;
   double            rr2;
   double            lots;
   double            riskMoney;
   double            riskPct;
   double            minLotRiskMoney;
   double            minLotRiskPct;
   double            spreadPct;
   double            quality;
   bool              riskWarn;
   datetime          createdAt;
   datetime          expiresAt;
   datetime          triggeredAt;
   datetime          closedAt;
   datetime          lastH4Checked;
  };

// Khai báo trước (định nghĩa trong AiExport.mqh): xuất JSON cho cầu nối AI
void AiExportEvent(const Setup &s,const string ev);
// Khai báo trước (định nghĩa trong Journal.mqh): nhật ký kết quả tín hiệu
void   JnlOnNewSetup(const Setup &s,const bool pending);
bool   JnlHasOpen(const string sym);
string JnlSummaryText();

Setup  g_setups[];      // setup đang mở + đã đóng gần đây (cooldown)
Setup  g_cands[];       // ứng viên nhóm phụ/khám phá chờ xếp hạng cuối vòng quét
string g_corrNames[];
string g_corrCodes[];   // "XAU,XAG,XPT"
int    g_sigDayKey=0;
int    g_sigNewToday=0;
bool   g_stateDirty=false;  // cần ghi lại file trạng thái
//--- thống kê trong ngày (theo múi giờ hiển thị) cho tóm tắt cuối ngày
int    g_dayNewPri=0;
int    g_dayNewOther=0;
int    g_dayTriggered=0;
int    g_dayInvalid=0;
int    g_dayExpired=0;
int    g_dayDone=0;
int    g_summarySentDay=0;

void SetupCopy(Setup &d,const Setup &s)
  {
   d.id=s.id;
   d.sym=s.sym;
   d.corrGroup=s.corrGroup;
   d.baseCcy=s.baseCcy;
   d.quoteCcy=s.quoteCcy;
   d.reasons=s.reasons;
   d.biasText=s.biasText;
   d.newsNote=s.newsNote;
   d.tier=s.tier;
   d.assetGroup=s.assetGroup;
   d.side=s.side;
   d.type=s.type;
   d.score=s.score;
   d.maxScore=s.maxScore;
   d.confluence=s.confluence;
   d.state=s.state;
   d.entryLow=s.entryLow;
   d.entryHigh=s.entryHigh;
   d.entryRef=s.entryRef;
   d.sl=s.sl;
   d.tp1=s.tp1;
   d.tp2=s.tp2;
   d.rr1=s.rr1;
   d.rr2=s.rr2;
   d.lots=s.lots;
   d.riskMoney=s.riskMoney;
   d.riskPct=s.riskPct;
   d.minLotRiskMoney=s.minLotRiskMoney;
   d.minLotRiskPct=s.minLotRiskPct;
   d.spreadPct=s.spreadPct;
   d.quality=s.quality;
   d.riskWarn=s.riskWarn;
   d.createdAt=s.createdAt;
   d.expiresAt=s.expiresAt;
   d.triggeredAt=s.triggeredAt;
   d.closedAt=s.closedAt;
   d.lastH4Checked=s.lastH4Checked;
  }

bool SigIsOpenState(const int st)
  {
   return (st==SS_ACTIVE || st==SS_TRIGGERED || st==SS_PENDING_RISK);
  }

bool SigCountsRisk(const int st)
  {
   return (st==SS_ACTIVE || st==SS_TRIGGERED);
  }

string SigStateName(const int st)
  {
   switch(st)
     {
      case SS_ACTIVE:       return "chờ Entry";
      case SS_TRIGGERED:    return "đã vào vùng";
      case SS_PENDING_RISK: return "chờ (vượt rủi ro)";
      case SS_INVALIDATED:  return "đã hủy";
      case SS_EXPIRED:      return "hết hạn";
      case SS_DONE:         return "đạt mục tiêu";
      default:              return "bỏ qua";
     }
  }

//+------------------------------------------------------------------+
//| Nhóm tương quan: "TÊN:CODE1,CODE2;TÊN2:..."                       |
//+------------------------------------------------------------------+
void SigInit()
  {
   ArrayResize(g_corrNames,0);
   ArrayResize(g_corrCodes,0);
   string groups[];
   int n=StringSplit(InpCorrelationGroups,';',groups);
   for(int i=0;i<n;i++)
     {
      string gdef=StrTrim(groups[i]);
      int p=StringFind(gdef,":");
      if(p<=0)
        {
         if(gdef!="")
            LogW("Nhóm tương quan sai cú pháp (cần TÊN:MÃ1,MÃ2): '"+gdef+"'");
         continue;
        }
      StrArrayPush(g_corrNames,StrTrim(StringSubstr(gdef,0,p)));
      StrArrayPush(g_corrCodes,StrUpper(StringSubstr(gdef,p+1)));
     }
   string list="";
   for(int i=0;i<ArraySize(g_corrNames);i++)
      list+=(i>0 ? " | " : "")+g_corrNames[i]+": "+g_corrCodes[i];
   LogI("Nhóm tương quan: "+(list=="" ? "(không có)" : list));
  }

string SigCorrGroupOf(const string base)
  {
   string up=StrUpper(base);
   int n=ArraySize(g_corrNames);
   for(int i=0;i<n;i++)
     {
      string codes[];
      int k=SplitCsv(g_corrCodes[i],codes);
      for(int j=0;j<k;j++)
         if(StrStartsWith(up,codes[j]))
            return g_corrNames[i];
     }
   return "";
  }

//+------------------------------------------------------------------+
//| Truy vấn                                                         |
//+------------------------------------------------------------------+
int SigFindOpen(const string sym)
  {
   int n=ArraySize(g_setups);
   for(int i=0;i<n;i++)
      if(g_setups[i].sym==sym && SigIsOpenState(g_setups[i].state))
         return i;
   return -1;
  }

bool SigHasOpen(const string sym)
  {
   return (SigFindOpen(sym)>=0);
  }

bool SigHasCandidate(const string sym)
  {
   int n=ArraySize(g_cands);
   for(int i=0;i<n;i++)
      if(g_cands[i].sym==sym)
         return true;
   return false;
  }

// Có thể tạo setup mới cho symbol? (không có setup mở, không trong cooldown)
bool SigCanCreate(const string sym,const datetime now,string &why)
  {
   int n=ArraySize(g_setups);
   for(int i=0;i<n;i++)
     {
      if(g_setups[i].sym!=sym)
         continue;
      if(SigIsOpenState(g_setups[i].state))
        {
         why="đang có setup "+g_setups[i].id;
         return false;
        }
      if(g_setups[i].closedAt>0 && (long)now-(long)g_setups[i].closedAt<(long)InpCooldownMinutes*60)
        {
         why=StringFormat("cooldown %d phút sau setup %s",InpCooldownMinutes,g_setups[i].id);
         return false;
        }
     }
   return true;
  }

double SigTotalRiskMoney()
  {
   double sum=0.0;
   int n=ArraySize(g_setups);
   for(int i=0;i<n;i++)
      if(SigCountsRisk(g_setups[i].state))
         sum+=g_setups[i].riskMoney;
   return sum;
  }

string SigTotalRiskText()
  {
   double sum=SigTotalRiskMoney();
   double bal=RiskBalance();
   string pct=(bal>0.0) ? DoubleToString(sum/bal*100.0,1)+"%" : "n/a";
   return "Tổng rủi ro các setup đang mở: "+FmtMoney(sum)+" ("+pct+")";
  }

int SigOpenCount()
  {
   int c=0;
   int n=ArraySize(g_setups);
   for(int i=0;i<n;i++)
      if(SigIsOpenState(g_setups[i].state))
         c++;
   return c;
  }

//+------------------------------------------------------------------+
//| Định dạng                                                        |
//+------------------------------------------------------------------+
string SigP(const Setup &s,const double price)
  {
   return FmtPrice(s.sym,price);
  }

string SigRR(const double rr)
  {
   if(rr==EMPTY_VALUE)
      return "n/a";
   return "1:"+DoubleToString(rr,1);
  }

string SigEntryLabel(const Setup &s)
  {
   if(s.type==STYPE_BREAKOUT)
      return (s.side>0) ? "Entry (Buy, thị trường/chờ retest)" : "Entry (Sell, thị trường/chờ retest)";
   return (s.side>0) ? "Entry (Buy Limit)" : "Entry (Sell Limit)";
  }

string SigInvalidText(const Setup &s)
  {
   return StringFormat("H4 đóng %s %s",(s.side>0) ? "dưới" : "trên",SigP(s,s.sl));
  }

string SigHeader(const Setup &s,const string kind)
  {
   return StringFormat("[%s] %s %s (%s) - Nhóm: %s",s.sym,kind,SideName(s.side),SetupTypeName(s.type),
                       TierName((ENUM_SYMBOL_TIER)s.tier));
  }

string SigLotLine(const Setup &s)
  {
   SymbolSpec sp;
   string lots=RiskGetSpec(s.sym,sp) ? FmtLots(sp,s.lots) : DoubleToString(s.lots,2);
   return StringFormat("Lot gợi ý: %s (rủi ro ≈ %s = %.1f%%)",lots,FmtMoney(s.riskMoney),s.riskPct);
  }

string SigCurrentPriceLine(const Setup &s)
  {
   return "Giá hiện tại: "+FmtPrice(s.sym,SymbolInfoDouble(s.sym,SYMBOL_BID))+" | Thời gian: "+
          FmtDisplayTime(TimeTradeServer());
  }

// Tin SETUP MỚI (pending=true: vượt ngưỡng tổng rủi ro, không phải tín hiệu vào lệnh)
string SigMsgNew(const Setup &s,const bool pending,const bool inZone)
  {
   string kind="SETUP";
   string head=SigHeader(s,kind);
   if(s.riskWarn)
      head+=" - CẢNH BÁO RỦI RO";
   if(pending)
      head+=" - ĐANG CHỜ, VƯỢT NGƯỠNG RỦI RO";
   string m=head+"\n";
   m+=SigCurrentPriceLine(s)+"\n";
   m+="Bias: "+s.biasText+"\n";
   m+=SigEntryLabel(s)+": "+SigP(s,s.entryLow)+" - "+SigP(s,s.entryHigh)+"\n";
   if(inZone)
      m+="Giá hiện đã nằm trong vùng Entry.\n";
   m+="SL: "+SigP(s,s.sl)+" (cách ~"+SigP(s,MathAbs(s.entryRef-s.sl))+")\n";
   m+="TP1: "+SigP(s,s.tp1)+" (RR "+SigRR(s.rr1)+")";
   if(s.tp2!=EMPTY_VALUE)
      m+=" | TP2: "+SigP(s,s.tp2)+" (RR "+SigRR(s.rr2)+")";
   m+="\n";
   m+=SigLotLine(s)+"\n";
   if(s.riskWarn)
     {
      SymbolSpec sp;
      string ml=RiskGetSpec(s.sym,sp) ? FmtLots(sp,sp.volMin) : "min";
      m+=StringFormat("Lot tối thiểu %s rủi ro ≈ %s (%.1f%%) vượt ngưỡng %.1f%%\n",ml,FmtMoney(s.minLotRiskMoney),
                      s.minLotRiskPct,InpRiskPerTradePct);
     }
   m+="Hủy kèo: "+SigInvalidText(s)+" | Hết hạn: "+IntegerToString(InpSetupExpiryHours)+"h\n";
   m+="Lý do: "+s.reasons+"\n";
   if(s.newsNote!="")
      m+=s.newsNote+"\n";
   if(pending)
      m+=StringFormat("Tổng rủi ro nếu thêm setup này vượt %.1f%% - KHÔNG phải tín hiệu vào lệnh.\n",InpMaxTotalRiskPct);
   m+=SigTotalRiskText()+"\n";
   m+="Chỉ là tín hiệu tham khảo, không phải lời khuyên đầu tư.";
   return m;
  }

string SigMsgEntry(const Setup &s)
  {
   string m=SigHeader(s,"GIÁ VÀO VÙNG ENTRY")+"\n";
   m+=SigCurrentPriceLine(s)+"\n";
   m+="Entry: "+SigP(s,s.entryLow)+" - "+SigP(s,s.entryHigh)+" | SL: "+SigP(s,s.sl)+"\n";
   m+="TP1: "+SigP(s,s.tp1)+(s.tp2!=EMPTY_VALUE ? " | TP2: "+SigP(s,s.tp2) : "")+"\n";
   m+=SigLotLine(s)+"\n";
   m+="Hủy kèo: "+SigInvalidText(s)+"\n";
   string news=NewsNoteFor(s.sym,TimeTradeServer());
   if(news!="")
      m+=news+"\n";
   m+="Chỉ là tín hiệu tham khảo, không phải lời khuyên đầu tư.";
   return m;
  }

string SigMsgClosed(const Setup &s,const string kind,const string reason)
  {
   string m=SigHeader(s,kind)+"\n";
   m+="Lý do: "+reason+"\n";
   m+="Entry: "+SigP(s,s.entryLow)+" - "+SigP(s,s.entryHigh)+" | SL: "+SigP(s,s.sl)+"\n";
   m+=SigCurrentPriceLine(s)+"\n";
   m+=SigTotalRiskText();
   return m;
  }

string SigSummaryRow(const Setup &s)
  {
   SymbolSpec sp;
   string lots=RiskGetSpec(s.sym,sp) ? FmtLots(sp,s.lots) : DoubleToString(s.lots,2);
   string flag=(s.state==SS_PENDING_RISK) ? " [CHỜ-RỦI RO]" : (s.riskWarn ? " [CẢNH BÁO RỦI RO]" : "");
   return StringFormat("%s [%s] %s %s | E %s-%s | SL %s | TP1 %s | %s lot | %s (%.1f%%)%s",
                       s.sym,TierName((ENUM_SYMBOL_TIER)s.tier),SideName(s.side),SetupTypeCode(s.type),
                       SigP(s,s.entryLow),SigP(s,s.entryHigh),SigP(s,s.sl),SigP(s,s.tp1),lots,
                       FmtMoney(s.riskMoney),s.riskPct,flag);
  }

//+------------------------------------------------------------------+
//| Dựng Setup từ kết quả phân tích. false = bị loại (log lý do)     |
//+------------------------------------------------------------------+
bool SigBuild(const SymbolRec &rec,const AnaResult &res,const SymbolSpec &sp,const double spreadPct,
              const datetime h4ClosedTime,Setup &s,string &why)
  {
   datetime now=TimeTradeServer();
   s.sym=rec.name;
   s.tier=(int)rec.tier;
   s.assetGroup=(int)rec.assetGroup;
   s.corrGroup=SigCorrGroupOf(rec.base);
   s.baseCcy=SymbolInfoString(rec.name,SYMBOL_CURRENCY_BASE);
   s.quoteCcy=SymbolInfoString(rec.name,SYMBOL_CURRENCY_PROFIT);
   s.side=res.geom.side;
   s.type=res.geom.type;
   s.score=IntAbs(res.score);
   s.maxScore=res.maxScore;
   s.confluence=res.geom.confluence;
   s.reasons=res.reasons;
   s.biasText=AnaBiasText(res);
   s.entryLow=res.geom.entryLow;
   s.entryHigh=res.geom.entryHigh;
   s.entryRef=res.geom.entryRef;
   s.sl=res.geom.sl;
   s.tp1=res.geom.tp1;
   s.tp2=res.geom.tp2;
   s.rr1=res.geom.rr1;
   s.rr2=res.geom.rr2;
   s.spreadPct=spreadPct;
   s.state=SS_ACTIVE;
   s.createdAt=now;
   s.expiresAt=(datetime)((long)now+(long)InpSetupExpiryHours*3600);
   s.triggeredAt=0;
   s.closedAt=0;
   s.lastH4Checked=h4ClosedTime;
   MqlDateTime dt;
   TimeToStruct(now,dt);
   s.id=StringFormat("%s-%04d%02d%02d%02d-%s-%s",s.sym,dt.year,dt.mon,dt.day,dt.hour,SideName(s.side),SetupTypeCode(s.type));

   //--- rủi ro theo SL thật
   double bal=RiskBalance();
   if(bal<=0.0)
     {
      why="chưa đọc được số dư tài khoản";
      return false;
     }
   double dist=MathAbs(s.entryRef-s.sl);
   s.minLotRiskMoney=RiskMoney(sp,dist,sp.volMin);
   s.minLotRiskPct=(bal>0.0) ? s.minLotRiskMoney/bal*100.0 : 0.0;
   if(bal>0.0 && s.minLotRiskPct>InpMaxMinLotRiskPct)
     {
      why=StringFormat("lot tối thiểu rủi ro ≈ %s (%.1f%%) > ngưỡng cứng %.1f%%",FmtMoney(s.minLotRiskMoney),
                       s.minLotRiskPct,InpMaxMinLotRiskPct);
      return false;
     }
   double lot=RiskLotForMoney(sp,dist,bal*InpRiskPerTradePct/100.0);
   s.riskWarn=(lot<=0.0);
   s.lots=s.riskWarn ? sp.volMin : lot;
   s.riskMoney=RiskMoney(sp,dist,s.lots);
   s.riskPct=(bal>0.0) ? s.riskMoney/bal*100.0 : 0.0;

   //--- điểm chất lượng để xếp hạng (0..100)
   double rrPart=MathMin(s.rr1,4.0)/4.0;
   double confPart=MathMin((double)s.confluence,4.0)/4.0;
   double spreadPart=MathMax(0.0,1.0-spreadPct/MathMax(InpMaxSpreadAtrPct,0.01));
   s.quality=40.0*s.score/IntMax(s.maxScore,1)+30.0*rrPart+20.0*confPart+10.0*spreadPart;

   s.newsNote=NewsNoteFor(s.sym,now);
   return true;
  }

//+------------------------------------------------------------------+
//| Các kiểm tra trước khi báo                                       |
//+------------------------------------------------------------------+
// Giá chưa chạy quá SL/TP1 kể từ lúc phân tích
bool SigStillValid(const Setup &s,string &why)
  {
   double bid=SymbolInfoDouble(s.sym,SYMBOL_BID);
   if(bid<=0.0)
     {
      why="không có báo giá";
      return false;
     }
   if(s.side<0)
     {
      if(bid>=s.sl) { why="giá đã vượt SL"; return false; }
      if(bid<=s.tp1) { why="giá đã chạy tới TP1"; return false; }
     }
   else
     {
      if(bid<=s.sl) { why="giá đã thủng SL"; return false; }
      if(bid>=s.tp1) { why="giá đã chạy tới TP1"; return false; }
     }
   return true;
  }

bool SigInZone(const Setup &s)
  {
   double bid=SymbolInfoDouble(s.sym,SYMBOL_BID);
   double ask=SymbolInfoDouble(s.sym,SYMBOL_ASK);
   if(s.side<0)
      return (bid>=s.entryLow);
   return (ask<=s.entryHigh && ask>0.0);
  }

// Nhóm phụ chỉ báo khi ưu tiên cùng nhóm không có setup; 1 setup/nhóm cho phụ/khám phá;
// không 2 setup ngược hướng trong cùng nhóm. Ưu tiên được "giành chỗ" setup phụ/khám phá chưa vào vùng.
bool SigCorrelationOk(const Setup &c,string &why)
  {
   if(c.corrGroup=="")
      return true;
   int n=ArraySize(g_setups);
   for(int i=0;i<n;i++)
     {
      if(!SigCountsRisk(g_setups[i].state) || g_setups[i].corrGroup!=c.corrGroup || g_setups[i].sym==c.sym)
         continue;
      bool opposite=(g_setups[i].side!=c.side);
      if(c.tier==TIER_PRIORITY)
        {
         if(!opposite)
            continue;
         if(g_setups[i].tier!=TIER_PRIORITY && g_setups[i].state==SS_ACTIVE)
            continue;   // sẽ bị hủy để nhường cho setup ưu tiên
         why=StringFormat("ngược hướng với %s %s đang hoạt động cùng nhóm %s",g_setups[i].sym,
                          SideName(g_setups[i].side),c.corrGroup);
         return false;
        }
      if(g_setups[i].tier==TIER_PRIORITY)
         why=StringFormat("cùng nhóm %s với setup ưu tiên %s đang hoạt động",c.corrGroup,g_setups[i].sym);
      else
         why=StringFormat("nhóm %s đã có setup %s %s (chỉ giữ 1 setup/nhóm)",c.corrGroup,g_setups[i].sym,
                          SideName(g_setups[i].side));
      return false;
     }
   return true;
  }

// Phơi nhiễm tiền tệ ròng cho Forex: mỗi đồng tiền tối đa N setup cùng phía
bool SigExposureOk(const Setup &c,string &why)
  {
   if(c.assetGroup!=AG_FOREX || c.baseCcy=="" || c.quoteCcy=="")
      return true;
   string longC=(c.side>0) ? c.baseCcy : c.quoteCcy;
   string shortC=(c.side>0) ? c.quoteCcy : c.baseCcy;
   int nLong=0,nShort=0;
   int n=ArraySize(g_setups);
   for(int i=0;i<n;i++)
     {
      if(!SigCountsRisk(g_setups[i].state) || g_setups[i].assetGroup!=AG_FOREX)
         continue;
      string l=(g_setups[i].side>0) ? g_setups[i].baseCcy : g_setups[i].quoteCcy;
      string s=(g_setups[i].side>0) ? g_setups[i].quoteCcy : g_setups[i].baseCcy;
      if(l==longC)
         nLong++;
      if(s==shortC)
         nShort++;
     }
   if(nLong+1>InpMaxCurrencySameSide)
     {
      why=StringFormat("phơi nhiễm: đã có %d setup MUA %s",nLong,longC);
      return false;
     }
   if(nShort+1>InpMaxCurrencySameSide)
     {
      why=StringFormat("phơi nhiễm: đã có %d setup BÁN %s",nShort,shortC);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Đóng setup + gửi tin                                             |
//+------------------------------------------------------------------+
void SigClose(const int i,const int newState,const string kind,const string reason,const bool notify)
  {
   g_setups[i].state=newState;
   g_setups[i].closedAt=TimeTradeServer();
   g_stateDirty=true;
   if(newState==SS_INVALIDATED)
      g_dayInvalid++;
   else if(newState==SS_EXPIRED)
      g_dayExpired++;
   else if(newState==SS_DONE)
      g_dayDone++;
   LogI(StringFormat("[%s] %s: %s (%s)",g_setups[i].sym,kind,reason,g_setups[i].id));
   if(notify)
      NotifySend(SigMsgClosed(g_setups[i],kind,reason));
  }

// Ưu tiên giành chỗ: hủy setup phụ/khám phá chưa vào vùng, ngược hướng, cùng nhóm
void SigYieldForPriority(const Setup &c)
  {
   if(c.tier!=TIER_PRIORITY || c.corrGroup=="")
      return;
   int n=ArraySize(g_setups);
   for(int i=0;i<n;i++)
     {
      if(g_setups[i].state!=SS_ACTIVE || g_setups[i].tier==TIER_PRIORITY)
         continue;
      if(g_setups[i].corrGroup!=c.corrGroup || g_setups[i].side==c.side || g_setups[i].sym==c.sym)
         continue;
      SigClose(i,SS_INVALIDATED,"HỦY KÈO","nhường cho setup ưu tiên "+c.sym+" "+SideName(c.side)+" ngược hướng",true);
     }
  }

int SigDayKeyNow()
  {
   MqlDateTime dt;
   TimeToStruct(ServerToDisplay(TimeTradeServer()),dt);
   return dt.year*10000+dt.mon*100+dt.day;
  }

void SigRollDay()
  {
   int k=SigDayKeyNow();
   if(k!=g_sigDayKey)
     {
      g_sigDayKey=k;
      g_sigNewToday=0;
      g_dayNewPri=0;
      g_dayNewOther=0;
      g_dayTriggered=0;
      g_dayInvalid=0;
      g_dayExpired=0;
      g_dayDone=0;
      g_stateDirty=true;
     }
  }

// Kiểm tra + ghi nhận setup. Trả về: 1 = active, 2 = pending rủi ro, 0 = bị loại
int SigAdmit(Setup &c,const bool sendDetail,bool &inZone,string &why)
  {
   inZone=false;
   if(!SigStillValid(c,why))
      return 0;
   if(!SigCorrelationOk(c,why))
      return 0;
   if(!SigExposureOk(c,why))
      return 0;
   SigYieldForPriority(c);
   double bal=RiskBalance();
   bool pending=(bal>0.0 && (SigTotalRiskMoney()+c.riskMoney)>bal*InpMaxTotalRiskPct/100.0);
   if(pending)
      c.state=SS_PENDING_RISK;
   else if(SigInZone(c))
     {
      c.state=SS_TRIGGERED;
      c.triggeredAt=TimeTradeServer();
      inZone=true;
     }
   int n=ArraySize(g_setups);
   ArrayResize(g_setups,n+1,16);
   SetupCopy(g_setups[n],c);
   g_stateDirty=true;
   if(c.tier==TIER_PRIORITY)
      g_dayNewPri++;
   else
      g_dayNewOther++;
   if(inZone)
      g_dayTriggered++;
   LogI(StringFormat("[%s] SETUP MỚI %s %s | điểm %d/%d | RR %.2f | chất lượng %.0f | %s (%s)",c.sym,SideName(c.side),
                     SetupTypeName(c.type),c.score,c.maxScore,c.rr1,c.quality,
                     pending ? "CHỜ - vượt ngưỡng rủi ro" : SigStateName(c.state),c.id));
   SymbolSpec sp;
   if(RiskGetSpec(c.sym,sp))
      LogI(StringFormat("[RISK] %s %s: %s%s",c.sym,c.id,
                        RiskBreakdown(c.sym,sp,MathAbs(c.entryRef-c.sl),c.lots,InpRiskPerTradePct),
                        c.riskWarn ? " | lot tối thiểu vượt mức -> CẢNH BÁO RỦI RO" : ""));
   if(sendDetail)
      NotifySend(SigMsgNew(g_setups[n],pending,inZone));
   // nhật ký ghi cả setup chờ rủi ro (đánh dấu riêng, không tính thống kê chính)
   JnlOnNewSetup(g_setups[n],pending);
   // setup "đang chờ, vượt ngưỡng rủi ro" không phải tín hiệu -> không gửi cho AI
   if(!pending)
      AiExportEvent(g_setups[n],"NEW_SETUP");
   return pending ? 2 : 1;
  }

//+------------------------------------------------------------------+
//| Ứng viên: ưu tiên báo ngay; phụ/khám phá chờ xếp hạng cuối vòng   |
//+------------------------------------------------------------------+
void SigOnCandidate(Setup &c)
  {
   if(c.tier==TIER_PRIORITY)
     {
      // danh sách ưu tiên luôn được báo (không tính top K / giới hạn ngày)
      bool inZone=false;
      string why="";
      if(SigAdmit(c,true,inZone,why)==0)
         LogI(StringFormat("[%s] setup ưu tiên %s không báo: %s",c.sym,SideName(c.side),why));
      return;
     }
   int n=ArraySize(g_cands);
   for(int i=0;i<n;i++)
     {
      if(g_cands[i].sym==c.sym)
        {
         SetupCopy(g_cands[i],c);
         return;
        }
     }
   ArrayResize(g_cands,n+1,16);
   SetupCopy(g_cands[n],c);
   LogD(StringFormat("[%s] ứng viên %s %s chờ xếp hạng (chất lượng %.0f)",c.sym,SideName(c.side),
                     SetupTypeName(c.type),c.quality));
  }

// Cuối vòng quét: xếp hạng, lấy top K, áp giới hạn ngày, gửi tin tổng hợp
void SigFlushRound(const datetime hk)
  {
   int n=ArraySize(g_cands);
   if(n==0)
      return;
   SigRollDay();
   //--- sắp xếp chỉ số theo chất lượng giảm dần
   int order[];
   ArrayResize(order,n);
   for(int i=0;i<n;i++)
      order[i]=i;
   for(int i=1;i<n;i++)
     {
      int v=order[i];
      int j=i-1;
      while(j>=0 && g_cands[order[j]].quality<g_cands[v].quality)
        {
         order[j+1]=order[j];
         j--;
        }
      order[j+1]=v;
     }
   int sentIdx[];
   int sent=0,skipCorr=0,skipTopK=0,skipDay=0,skipOther=0;
   for(int r=0;r<n;r++)
     {
      int ci=order[r];
      string why="";
      if(sent>=InpTopK)
        {
         skipTopK++;
         LogI(StringFormat("[%s] ứng viên bỏ qua: ngoài top %d (chất lượng %.0f)",g_cands[ci].sym,InpTopK,g_cands[ci].quality));
         continue;
        }
      if(g_sigNewToday>=InpMaxNewPerDay)
        {
         skipDay++;
         LogI(StringFormat("[%s] ứng viên bỏ qua: đã đạt giới hạn %d tin/ngày",g_cands[ci].sym,InpMaxNewPerDay));
         continue;
        }
      string cwhy="";
      if(!SigCanCreate(g_cands[ci].sym,TimeTradeServer(),cwhy))
        {
         skipOther++;
         continue;
        }
      bool inZone=false;
      int res=SigAdmit(g_cands[ci],false,inZone,why);
      if(res==0)
        {
         if(StringFind(why,"nhóm")>=0 || StringFind(why,"phơi nhiễm")>=0)
            skipCorr++;
         else
            skipOther++;
         LogI(StringFormat("[%s] ứng viên bỏ qua: %s",g_cands[ci].sym,why));
         continue;
        }
      int k=ArraySize(sentIdx);
      ArrayResize(sentIdx,k+1);
      sentIdx[k]=ArraySize(g_setups)-1;
      sent++;
      g_sigNewToday++;
     }
   //--- nhả Market Watch cho ứng viên không được báo (EA tự thêm, nhóm khám phá)
   string done[];
   for(int r=0;r<n;r++)
      StrArrayPush(done,g_cands[r].sym);
   ArrayResize(g_cands,0);
   for(int r=0;r<n;r++)
     {
      if(SigHasOpen(done[r]) || JnlHasOpen(done[r]))
         continue;
      int ui=UniFind(done[r]);
      if(ui>=0)
         UniReleaseIfOwned(ui);
     }
   if(sent==0)
     {
      LogI(StringFormat("Vòng quét %s: %d ứng viên, không có setup mới được báo.",TimeToString(hk,TIME_DATE|TIME_MINUTES),n));
      return;
     }
   if(sent==1)
     {
      int i=sentIdx[0];
      bool inZone=(g_setups[i].state==SS_TRIGGERED);
      NotifySend(SigMsgNew(g_setups[i],g_setups[i].state==SS_PENDING_RISK,inZone));
      return;
     }
   string m=StringFormat("[TỔNG HỢP] %d setup mới - %s\n",sent,FmtDisplayTime(TimeTradeServer()));
   m+="Cặp | Hướng | Entry | SL | TP1 | Lot | Rủi ro\n";
   for(int k=0;k<sent;k++)
      m+=SigSummaryRow(g_setups[sentIdx[k]])+"\n";
   int skipped=skipCorr+skipTopK+skipDay+skipOther;
   if(skipped>0)
      m+=StringFormat("Bỏ qua %d ứng viên (tương quan/phơi nhiễm %d, ngoài top %d: %d, giới hạn ngày %d, khác %d)\n",
                      skipped,skipCorr,InpTopK,skipTopK,skipDay,skipOther);
   m+=StringFormat("Tin mới hôm nay (phụ/khám phá): %d/%d\n",g_sigNewToday,InpMaxNewPerDay);
   m+=SigTotalRiskText()+"\n";
   m+="Chỉ là tín hiệu tham khảo, không phải lời khuyên đầu tư.";
   NotifySend(m);
  }

// Bỏ setup đã đóng quá lâu (giữ để tính cooldown)
void SigPrune(const datetime now)
  {
   long keep=(long)InpCooldownMinutes*60;
   if(keep<86400)
      keep=86400;
   int n=ArraySize(g_setups);
   int w=0;
   for(int i=0;i<n;i++)
     {
      bool drop=(!SigIsOpenState(g_setups[i].state) && g_setups[i].closedAt>0 &&
                 (long)now-(long)g_setups[i].closedAt>keep);
      if(drop)
         continue;
      if(w!=i)
         SetupCopy(g_setups[w],g_setups[i]);
      w++;
     }
   if(w!=n)
     {
      ArrayResize(g_setups,w);
      g_stateDirty=true;
     }
  }

//+------------------------------------------------------------------+
//| Theo dõi setup mỗi chu kỳ (nhẹ: chỉ đọc bid/ask + 1 nến H4)      |
//+------------------------------------------------------------------+
void SigMonitor(const datetime now)
  {
   int n=ArraySize(g_setups);
   for(int i=0;i<n;i++)
     {
      if(!SigIsOpenState(g_setups[i].state))
         continue;
      string sym=g_setups[i].sym;
      double bid=SymbolInfoDouble(sym,SYMBOL_BID);
      double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
      if(bid<=0.0 || ask<=0.0)
         continue;
      int side=g_setups[i].side;

      //--- setup chờ do vượt rủi ro: chỉ hết hạn, không theo dõi giá
      if(g_setups[i].state==SS_PENDING_RISK)
        {
         if(now>=g_setups[i].expiresAt)
            SigClose(i,SS_EXPIRED,"HẾT HẠN","setup chờ (vượt rủi ro) hết hạn",false);
         continue;
        }

      //--- hủy kèo: nến H4 đóng vượt SL (xét cả các nến bị bỏ lỡ, ví dụ khi EA tắt)
      MqlRates last[];
      if(CopyRates(sym,PERIOD_H4,1,1,last)==1 && last[0].time>g_setups[i].lastH4Checked)
        {
         MqlRates r[];
         int cnt=1;
         if((long)last[0].time-(long)g_setups[i].lastH4Checked>4*3600 && g_setups[i].lastH4Checked>0)
            cnt=60;
         int got=(cnt==1) ? CopyRates(sym,PERIOD_H4,1,1,r) : CopyRates(sym,PERIOD_H4,1,cnt,r);
         bool broken=false;
         double brokeClose=0.0;
         // r[] không phải series: cũ -> mới
         for(int b=0;b<got && !broken;b++)
           {
            if(r[b].time<=g_setups[i].lastH4Checked)
               continue;
            if((side<0) ? (r[b].close>g_setups[i].sl) : (r[b].close<g_setups[i].sl))
              {
               broken=true;
               brokeClose=r[b].close;
              }
           }
         g_setups[i].lastH4Checked=last[0].time;
         g_stateDirty=true;
         if(broken)
           {
            SigClose(i,SS_INVALIDATED,"HỦY KÈO",StringFormat("H4 đóng %s %s mức hủy %s",FmtPrice(sym,brokeClose),
                     (side<0) ? "trên" : "dưới",FmtPrice(sym,g_setups[i].sl)),true);
            continue;
           }
        }

      if(g_setups[i].state==SS_ACTIVE)
        {
         //--- giá vào vùng Entry
         bool touched=(side<0) ? (bid>=g_setups[i].entryLow) : (ask<=g_setups[i].entryHigh);
         if(touched)
           {
            g_setups[i].state=SS_TRIGGERED;
            g_setups[i].triggeredAt=now;
            g_stateDirty=true;
            g_dayTriggered++;
            LogI(StringFormat("[%s] GIÁ VÀO VÙNG ENTRY (%s)",sym,g_setups[i].id));
            NotifySend(SigMsgEntry(g_setups[i]));
            AiExportEvent(g_setups[i],"ENTRY_TOUCHED");
            continue;
           }
         //--- giá chạy tới TP1 trước khi vào vùng -> lỡ kèo
         bool missed=(side<0) ? (bid<=g_setups[i].tp1) : (bid>=g_setups[i].tp1);
         if(missed)
           {
            SigClose(i,SS_INVALIDATED,"HỦY KÈO","giá chạy tới TP1 trước khi vào vùng Entry",true);
            continue;
           }
         if(now>=g_setups[i].expiresAt)
           {
            SigClose(i,SS_EXPIRED,"HẾT HẠN",StringFormat("giá không vào vùng Entry sau %dh",InpSetupExpiryHours),true);
            continue;
           }
        }
      else if(g_setups[i].state==SS_TRIGGERED)
        {
         double target=(g_setups[i].tp2!=EMPTY_VALUE) ? g_setups[i].tp2 : g_setups[i].tp1;
         bool hit=(side<0) ? (bid<=target) : (bid>=target);
         if(hit)
           {
            SigClose(i,SS_DONE,"ĐẠT MỤC TIÊU","giá chạm "+FmtPrice(sym,target),false);
            continue;
           }
         if((long)now-(long)g_setups[i].triggeredAt>=(long)InpTriggeredMaxHours*3600)
            SigClose(i,SS_EXPIRED,"HẾT HẠN",StringFormat("đã vào vùng Entry quá %dh, ngừng theo dõi",InpTriggeredMaxHours),true);
        }
     }
   SigPrune(now);
  }

//+------------------------------------------------------------------+
//| Tóm tắt cuối ngày (1 lần/ngày, sau InpDailySummaryHour GMT+x)     |
//+------------------------------------------------------------------+
void SigDailySummaryCheck(const datetime now)
  {
   if(!InpDailySummary)
      return;
   MqlDateTime dt;
   TimeToStruct(ServerToDisplay(now),dt);
   int key=dt.year*10000+dt.mon*100+dt.day;
   if(dt.hour<InpDailySummaryHour || g_summarySentDay==key)
      return;
   g_summarySentDay=key;
   g_stateDirty=true;
   string m=StringFormat("[%s] TÓM TẮT NGÀY %02d/%02d (%s)\n",EA_NAME,dt.day,dt.mon,g_displayTzLabel);
   m+=StringFormat("Setup mới: Ưu tiên %d | Phụ/Khám phá %d (giới hạn %d)\n",g_dayNewPri,g_dayNewOther,InpMaxNewPerDay);
   m+=StringFormat("Vào vùng Entry: %d | Hủy kèo: %d | Hết hạn: %d | Đạt mục tiêu: %d\n",
                   g_dayTriggered,g_dayInvalid,g_dayExpired,g_dayDone);
   int open=SigOpenCount();
   m+=StringFormat("Setup đang mở (%d):\n",open);
   int n=ArraySize(g_setups);
   for(int i=0;i<n;i++)
     {
      if(!SigIsOpenState(g_setups[i].state))
         continue;
      m+=StringFormat("- %s %s %s [%s] E %s-%s | SL %s | TP1 %s\n",g_setups[i].sym,SideName(g_setups[i].side),
                      SetupTypeCode(g_setups[i].type),SigStateName(g_setups[i].state),
                      SigP(g_setups[i],g_setups[i].entryLow),SigP(g_setups[i],g_setups[i].entryHigh),
                      SigP(g_setups[i],g_setups[i].sl),SigP(g_setups[i],g_setups[i].tp1));
     }
   m+=SigTotalRiskText()+"\n";
   string jt=JnlSummaryText();
   if(jt!="")
      m+=jt+"\n";
   m+="Số dư: "+FmtMoney(RiskBalance())+" | Telegram: "+TgStatusText()+"\n";
   m+="Chỉ là tín hiệu tham khảo, không phải lời khuyên đầu tư.";
   NotifySend(m);
  }

// Dòng cho bảng trạng thái
string SigPanelText()
  {
   double bal=RiskBalance();
   double sum=SigTotalRiskMoney();
   string s=StringFormat("--- Setup mở: %d | tổng rủi ro %s (%s) | tin phụ/khám phá hôm nay %d/%d ---\n",
                         SigOpenCount(),FmtMoney(sum),(bal>0.0) ? DoubleToString(sum/bal*100.0,1)+"%" : "n/a",
                         g_sigNewToday,InpMaxNewPerDay);
   int n=ArraySize(g_setups);
   for(int i=0;i<n;i++)
     {
      if(!SigIsOpenState(g_setups[i].state))
         continue;
      s+=StringFormat("%s %s %s [%s] E %s-%s SL %s TP1 %s\n",g_setups[i].sym,SideName(g_setups[i].side),
                      SetupTypeCode(g_setups[i].type),SigStateName(g_setups[i].state),
                      SigP(g_setups[i],g_setups[i].entryLow),SigP(g_setups[i],g_setups[i].entryHigh),
                      SigP(g_setups[i],g_setups[i].sl),SigP(g_setups[i],g_setups[i].tp1));
     }
   return s;
  }

#endif
