//+------------------------------------------------------------------+
//| Journal.mqh - nhật ký kết quả tín hiệu                            |
//| Mỗi setup đã báo được "mô phỏng" trên nến M1 (giá bid + spread):  |
//|  - Khớp khi giá chạm entry_ref (giữa vùng Entry, mức dùng tính RR) |
//|  - SL và TP cùng trong 1 nến -> coi như SL trước (thận trọng)      |
//|  - Nến khớp: chỉ xét SL, TP tính từ nến sau                        |
//| 3 kịch bản thoát lệnh (tính theo R = khoảng cách Entry-SL):       |
//|  A: chốt toàn bộ ở TP1                                           |
//|  B: chốt toàn bộ ở TP2 (không có TP2 thì dùng TP1)                |
//|  C: 50% chốt TP1, 50% còn lại dời SL về hòa vốn, chờ TP2           |
//| Kết quả ghi vào MQL5/Files/SignalEA/journal_<login>.csv.          |
//| Include SAU Signals/State/AiExport.                              |
//+------------------------------------------------------------------+
#ifndef SIGNALEA_JOURNAL_MQH
#define SIGNALEA_JOURNAL_MQH

#include "Common.mqh"
#include "Signals.mqh"
#include "State.mqh"
#include "AiExport.mqh"

#define JP_WAIT    0   // chờ khớp
#define JP_TRADE   1   // đã khớp, đang chạy
#define JP_CLOSED  2
#define JNL_FIELDS 34
#define JNL_MAX_BARS 20000

struct JnlRec
  {
   string            id;
   string            sym;
   int               tier;
   int               assetGroup;
   int               side;
   int               type;
   int               score;
   int               maxScore;
   bool              pending;      // setup "đang chờ, vượt ngưỡng rủi ro" (không tính thống kê chính)
   bool              riskWarn;
   double            entry;
   double            sl;
   double            tp1;
   double            tp2;
   double            rr1;
   double            rr2;
   double            spread;
   double            lots;
   double            riskMoney;
   double            riskPct;
   datetime          createdAt;
   datetime          lastBar;      // nến M1 đã xử lý gần nhất
   datetime          fillTime;
   datetime          closeTime;
   int               phase;
   double            rA;           // EMPTY_VALUE = chưa có kết quả
   double            rB;
   double            rC1;          // nửa đầu kịch bản C
   double            rC2;          // nửa sau kịch bản C
   bool              c2Active;
   double            mfe;          // đi thuận lớn nhất (giá)
   double            mae;          // đi ngược lớn nhất (giá)
   string            outcome;
   string            note;
  };

JnlRec   g_jnl[];
bool     g_jnlDirty=false;
bool     g_jnlLoaded=false;
string   g_jnlStateFile="";
//--- thống kê tích lũy (chỉ tín hiệu thật)
int      g_jsClosed=0;
int      g_jsFilled=0;
int      g_jsWinA=0;
int      g_jsWinB=0;
double   g_jsSumA=0.0;
double   g_jsSumB=0.0;
double   g_jsSumC=0.0;
double   g_jsMoneyA=0.0;
//--- trong ngày (múi giờ hiển thị)
int      g_jdKey=0;
int      g_jdClosed=0;
double   g_jdSumA=0.0;

void JnlCopy(JnlRec &d,const JnlRec &s)
  {
   d.id=s.id;
   d.sym=s.sym;
   d.tier=s.tier;
   d.assetGroup=s.assetGroup;
   d.side=s.side;
   d.type=s.type;
   d.score=s.score;
   d.maxScore=s.maxScore;
   d.pending=s.pending;
   d.riskWarn=s.riskWarn;
   d.entry=s.entry;
   d.sl=s.sl;
   d.tp1=s.tp1;
   d.tp2=s.tp2;
   d.rr1=s.rr1;
   d.rr2=s.rr2;
   d.spread=s.spread;
   d.lots=s.lots;
   d.riskMoney=s.riskMoney;
   d.riskPct=s.riskPct;
   d.createdAt=s.createdAt;
   d.lastBar=s.lastBar;
   d.fillTime=s.fillTime;
   d.closeTime=s.closeTime;
   d.phase=s.phase;
   d.rA=s.rA;
   d.rB=s.rB;
   d.rC1=s.rC1;
   d.rC2=s.rC2;
   d.c2Active=s.c2Active;
   d.mfe=s.mfe;
   d.mae=s.mae;
   d.outcome=s.outcome;
   d.note=s.note;
  }

bool JnlHasOpen(const string sym)
  {
   int n=ArraySize(g_jnl);
   for(int i=0;i<n;i++)
      if(g_jnl[i].sym==sym && g_jnl[i].phase!=JP_CLOSED)
         return true;
   return false;
  }

int JnlOpenCount(int &waiting,int &trading)
  {
   waiting=0;
   trading=0;
   int n=ArraySize(g_jnl);
   for(int i=0;i<n;i++)
     {
      if(g_jnl[i].phase==JP_WAIT)
         waiting++;
      else if(g_jnl[i].phase==JP_TRADE)
         trading++;
     }
   return waiting+trading;
  }

void JnlRollDay()
  {
   int k=SigDayKeyNow();
   if(k!=g_jdKey)
     {
      g_jdKey=k;
      g_jdClosed=0;
      g_jdSumA=0.0;
      g_jnlDirty=true;
     }
  }

//+------------------------------------------------------------------+
//| Tạo bản ghi khi setup được báo (gọi từ SigAdmit)                 |
//+------------------------------------------------------------------+
void JnlOnNewSetup(const Setup &s,const bool pending)
  {
   if(!InpJournalEnabled)
      return;
   if(MathAbs(s.entryRef-s.sl)<=0.0)
      return;
   int n=ArraySize(g_jnl);
   ArrayResize(g_jnl,n+1,16);
   g_jnl[n].id=s.id;
   g_jnl[n].sym=s.sym;
   g_jnl[n].tier=s.tier;
   g_jnl[n].assetGroup=s.assetGroup;
   g_jnl[n].side=s.side;
   g_jnl[n].type=s.type;
   g_jnl[n].score=s.score;
   g_jnl[n].maxScore=s.maxScore;
   g_jnl[n].pending=pending;
   g_jnl[n].riskWarn=s.riskWarn;
   g_jnl[n].entry=s.entryRef;
   g_jnl[n].sl=s.sl;
   g_jnl[n].tp1=s.tp1;
   g_jnl[n].tp2=s.tp2;
   g_jnl[n].rr1=s.rr1;
   g_jnl[n].rr2=s.rr2;
   double sp=SymbolInfoDouble(s.sym,SYMBOL_ASK)-SymbolInfoDouble(s.sym,SYMBOL_BID);
   g_jnl[n].spread=(sp>0.0) ? sp : 0.0;
   g_jnl[n].lots=s.lots;
   g_jnl[n].riskMoney=s.riskMoney;
   g_jnl[n].riskPct=s.riskPct;
   g_jnl[n].createdAt=s.createdAt;
   g_jnl[n].lastBar=(datetime)((long)s.createdAt-((long)s.createdAt%60));
   g_jnl[n].fillTime=0;
   g_jnl[n].closeTime=0;
   g_jnl[n].phase=JP_WAIT;
   g_jnl[n].rA=EMPTY_VALUE;
   g_jnl[n].rB=EMPTY_VALUE;
   g_jnl[n].rC1=EMPTY_VALUE;
   g_jnl[n].rC2=EMPTY_VALUE;
   g_jnl[n].c2Active=false;
   g_jnl[n].mfe=0.0;
   g_jnl[n].mae=0.0;
   g_jnl[n].outcome="";
   g_jnl[n].note="";
   g_jnlDirty=true;
   LogD("[JOURNAL] bắt đầu theo dõi "+s.id);
  }

//+------------------------------------------------------------------+
//| Kiểm tra chạm giá trong 1 nến (nến là giá bid)                   |
//+------------------------------------------------------------------+
bool JnlHitSL(const JnlRec &j,const MqlRates &b)
  {
   if(j.side<0)
      return (b.high+j.spread>=j.sl);     // Sell: SL khớp theo ask
   return (b.low<=j.sl);                   // Buy: SL khớp theo bid
  }

bool JnlHitTarget(const JnlRec &j,const MqlRates &b,const double target)
  {
   if(j.side<0)
      return (b.low+j.spread<=target);
   return (b.high>=target);
  }

bool JnlHitBreakEven(const JnlRec &j,const MqlRates &b)
  {
   if(j.side<0)
      return (b.high+j.spread>=j.entry);
   return (b.low<=j.entry);
  }

double JnlRisk(const JnlRec &j)
  {
   return MathAbs(j.entry-j.sl);
  }

double JnlMarkR(const JnlRec &j,const double close)
  {
   double risk=JnlRisk(j);
   if(risk<=0.0)
      return 0.0;
   if(j.side<0)
      return (j.entry-(close+j.spread))/risk;
   return (close-j.entry)/risk;
  }

void JnlTrackExcursion(const int i,const MqlRates &b,const bool fillBar=false)
  {
   double fav,adv;
   if(g_jnl[i].side<0)
     {
      fav=g_jnl[i].entry-(b.low+g_jnl[i].spread);
      adv=(b.high+g_jnl[i].spread)-g_jnl[i].entry;
     }
   else
     {
      fav=b.high-g_jnl[i].entry;
      adv=g_jnl[i].entry-b.low;
     }
   // nến khớp: không biết giá đi thuận trước hay sau lúc khớp -> chỉ tính MAE
   if(!fillBar && fav>g_jnl[i].mfe)
      g_jnl[i].mfe=fav;
   if(adv>g_jnl[i].mae)
      g_jnl[i].mae=adv;
  }

//+------------------------------------------------------------------+
//| CSV                                                              |
//+------------------------------------------------------------------+
string JnlFileBase()
  {
   return EA_FILES_DIR+"\\journal_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
  }

string JnlTime(const datetime serverTime)
  {
   if(serverTime==0)
      return "";
   MqlDateTime dt;
   TimeToStruct(ServerToDisplay(serverTime),dt);
   return StringFormat("%04d-%02d-%02d %02d:%02d",dt.year,dt.mon,dt.day,dt.hour,dt.min);
  }

string JnlNum(const double v,const int dec)
  {
   if(v==EMPTY_VALUE || !MathIsValidNumber(v))
      return "";
   return DoubleToString(v,dec);
  }

string JnlCsvText(const string s)
  {
   string t=s;
   StringReplace(t,";",",");
   StringReplace(t,"\n"," ");
   StringReplace(t,"\r"," ");
   return t;
  }

bool JnlAppendCsv(const string line)
  {
   string fname=JnlFileBase()+".csv";
   ResetLastError();
   int h=FileOpen(fname,FILE_READ|FILE_WRITE|FILE_BIN|FILE_SHARE_READ);
   if(h==INVALID_HANDLE)
     {
      LogE(StringFormat("[JOURNAL] Không mở được %s (lỗi %d).",fname,GetLastError()));
      return false;
     }
   string text="";
   if(FileSize(h)==0)
      text=ShortToString(0xFEFF)+"id;symbol;tier;group;side;type;pending_risk;score;max_score;created;entry;sl;tp1;tp2;rr1;rr2;"+
           "spread;lot;risk_money;risk_pct;risk_warning;filled;fill_time;minutes_to_fill;outcome;r_a;r_b;r_c;"+
           "mfe_r;mae_r;hold_hours;close_time;money_a;note\r\n";
   text+=line+"\r\n";
   uchar bytes[];
   int n=StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8);
   if(n>0 && bytes[n-1]==0)
      n--;
   FileSeek(h,0,SEEK_END);
   FileWriteArray(h,bytes,0,n);
   FileClose(h);
   return true;
  }

string JnlCsvLine(const JnlRec &j)
  {
   int dg=(int)SymbolInfoInteger(j.sym,SYMBOL_DIGITS);
   double risk=JnlRisk(j);
   bool filled=(j.fillTime>0);
   double rC=(j.rC1!=EMPTY_VALUE && j.rC2!=EMPTY_VALUE) ? 0.5*(j.rC1+j.rC2) : EMPTY_VALUE;
   string mtf=filled ? IntegerToString((int)(((long)j.fillTime-(long)j.createdAt)/60)) : "";
   string hold=filled ? DoubleToString(((double)((long)j.closeTime-(long)j.fillTime))/3600.0,1) : "";
   string mfeR=(filled && risk>0.0) ? DoubleToString(j.mfe/risk,2) : "";
   string maeR=(filled && risk>0.0) ? DoubleToString(j.mae/risk,2) : "";
   string moneyA=(j.rA!=EMPTY_VALUE) ? DoubleToString(j.rA*j.riskMoney,2) : "";
   string f[];
   ArrayResize(f,JNL_FIELDS);
   f[0]=j.id;
   f[1]=j.sym;
   f[2]=AiTierCode(j.tier);
   f[3]=AiGroupCode(j.assetGroup);
   f[4]=(j.side>0) ? "buy" : "sell";
   f[5]=(j.type==STYPE_BREAKOUT) ? "breakout" : "pullback";
   f[6]=j.pending ? "1" : "0";
   f[7]=IntegerToString(j.score);
   f[8]=IntegerToString(j.maxScore);
   f[9]=JnlTime(j.createdAt);
   f[10]=JnlNum(j.entry,dg);
   f[11]=JnlNum(j.sl,dg);
   f[12]=JnlNum(j.tp1,dg);
   f[13]=JnlNum(j.tp2,dg);
   f[14]=JnlNum(j.rr1,2);
   f[15]=JnlNum(j.rr2,2);
   f[16]=JnlNum(j.spread,dg);
   f[17]=JnlNum(j.lots,2);
   f[18]=JnlNum(j.riskMoney,2);
   f[19]=JnlNum(j.riskPct,2);
   f[20]=j.riskWarn ? "1" : "0";
   f[21]=filled ? "1" : "0";
   f[22]=JnlTime(j.fillTime);
   f[23]=mtf;
   f[24]=j.outcome;
   f[25]=JnlNum(j.rA,2);
   f[26]=JnlNum(j.rB,2);
   f[27]=JnlNum(rC,2);
   f[28]=mfeR;
   f[29]=maeR;
   f[30]=hold;
   f[31]=JnlTime(j.closeTime);
   f[32]=moneyA;
   f[33]=JnlCsvText(j.note);
   string line="";
   for(int k=0;k<JNL_FIELDS;k++)
      line+=(k>0 ? ";" : "")+f[k];
   return line;
  }

//+------------------------------------------------------------------+
//| Đóng bản ghi: ghi CSV + cập nhật thống kê                        |
//+------------------------------------------------------------------+
void JnlFinish(const int i,const datetime when,const string outcome,const string note)
  {
   g_jnl[i].phase=JP_CLOSED;
   g_jnl[i].closeTime=when;
   g_jnl[i].outcome=outcome;
   g_jnl[i].note=note;
   g_jnlDirty=true;
   JnlAppendCsv(JnlCsvLine(g_jnl[i]));
   bool filled=(g_jnl[i].fillTime>0);
   string res="không khớp";
   if(filled)
     {
      double rC=0.5*(g_jnl[i].rC1+g_jnl[i].rC2);
      res=StringFormat("A %+.2fR | B %+.2fR | C %+.2fR",g_jnl[i].rA,g_jnl[i].rB,rC);
     }
   LogI(StringFormat("[JOURNAL] %s: %s (%s)%s%s",g_jnl[i].id,outcome,res,
                     note=="" ? "" : " - "+note,g_jnl[i].pending ? " [setup chờ rủi ro, không tính thống kê]" : ""));
   if(g_jnl[i].pending)
      return;
   JnlRollDay();
   g_jsClosed++;
   g_jdClosed++;
   if(!filled)
      return;
   g_jsFilled++;
   g_jsSumA+=g_jnl[i].rA;
   g_jsSumB+=g_jnl[i].rB;
   g_jsSumC+=0.5*(g_jnl[i].rC1+g_jnl[i].rC2);
   g_jsMoneyA+=g_jnl[i].rA*g_jnl[i].riskMoney;
   g_jdSumA+=g_jnl[i].rA;
   if(g_jnl[i].rA>0.0)
      g_jsWinA++;
   if(g_jnl[i].rB>0.0)
      g_jsWinB++;
  }

bool JnlAllResolved(const JnlRec &j)
  {
   return (j.rA!=EMPTY_VALUE && j.rB!=EMPTY_VALUE && j.rC1!=EMPTY_VALUE && j.rC2!=EMPTY_VALUE);
  }

string JnlOutcomeLabel(const JnlRec &j)
  {
   if(j.rA<0.0)
      return "SL";
   if(j.tp2==EMPTY_VALUE)
      return "TP1";
   if(j.rB>0.0)
      return "TP2";
   return "TP1_SL";   // chạm TP1 rồi quay về SL
  }

//+------------------------------------------------------------------+
//| Áp 1 nến M1 đã đóng vào bản ghi                                  |
//+------------------------------------------------------------------+
void JnlApplyBar(const int i,const MqlRates &b)
  {
   if(g_jnl[i].phase==JP_WAIT)
     {
      bool filled=(g_jnl[i].side<0) ? (b.high>=g_jnl[i].entry) : (b.low+g_jnl[i].spread<=g_jnl[i].entry);
      if(!filled)
         return;
      g_jnl[i].phase=JP_TRADE;
      g_jnl[i].fillTime=b.time;
      g_jnlDirty=true;
      JnlTrackExcursion(i,b,true);
      // nến khớp: chỉ xét SL (không biết giá chạy theo thứ tự nào trong nến)
      if(JnlHitSL(g_jnl[i],b))
        {
         g_jnl[i].rA=-1.0;
         g_jnl[i].rB=-1.0;
         g_jnl[i].rC1=-1.0;
         g_jnl[i].rC2=-1.0;
         JnlFinish(i,b.time,"SL","chạm SL ngay trong nến khớp");
        }
      return;
     }
   if(g_jnl[i].phase!=JP_TRADE)
      return;

   JnlTrackExcursion(i,b);
   bool sl=JnlHitSL(g_jnl[i],b);
   bool hasTp2=(g_jnl[i].tp2!=EMPTY_VALUE);
   double t2=hasTp2 ? g_jnl[i].tp2 : g_jnl[i].tp1;
   double r2=hasTp2 ? g_jnl[i].rr2 : g_jnl[i].rr1;

   //--- A: toàn bộ ở TP1
   if(g_jnl[i].rA==EMPTY_VALUE)
     {
      if(sl)
         g_jnl[i].rA=-1.0;
      else if(JnlHitTarget(g_jnl[i],b,g_jnl[i].tp1))
         g_jnl[i].rA=g_jnl[i].rr1;
     }
   //--- B: toàn bộ ở TP2
   if(g_jnl[i].rB==EMPTY_VALUE)
     {
      if(sl)
         g_jnl[i].rB=-1.0;
      else if(JnlHitTarget(g_jnl[i],b,t2))
         g_jnl[i].rB=r2;
     }
   //--- C: 50% TP1, 50% dời SL hòa vốn chờ TP2 (nửa sau xét từ nến kế tiếp)
   if(g_jnl[i].rC1==EMPTY_VALUE)
     {
      if(sl)
        {
         g_jnl[i].rC1=-1.0;
         g_jnl[i].rC2=-1.0;
        }
      else if(JnlHitTarget(g_jnl[i],b,g_jnl[i].tp1))
        {
         g_jnl[i].rC1=g_jnl[i].rr1;
         if(hasTp2)
            g_jnl[i].c2Active=true;
         else
            g_jnl[i].rC2=g_jnl[i].rr1;
        }
     }
   else if(g_jnl[i].rC2==EMPTY_VALUE && g_jnl[i].c2Active)
     {
      if(JnlHitBreakEven(g_jnl[i],b))
         g_jnl[i].rC2=0.0;
      else if(JnlHitTarget(g_jnl[i],b,t2))
         g_jnl[i].rC2=r2;
     }

   if(JnlAllResolved(g_jnl[i]))
     {
      JnlFinish(i,b.time,JnlOutcomeLabel(g_jnl[i]),"");
      return;
     }
   //--- quá thời gian giữ lệnh: chốt theo giá đóng cửa nến
   if((long)b.time-(long)g_jnl[i].fillTime>=(long)InpJournalMaxHoldHours*3600)
     {
      double mark=JnlMarkR(g_jnl[i],b.close);
      if(g_jnl[i].rA==EMPTY_VALUE)
         g_jnl[i].rA=mark;
      if(g_jnl[i].rB==EMPTY_VALUE)
         g_jnl[i].rB=mark;
      if(g_jnl[i].rC1==EMPTY_VALUE)
         g_jnl[i].rC1=mark;
      if(g_jnl[i].rC2==EMPTY_VALUE)
         g_jnl[i].rC2=mark;
      JnlFinish(i,b.time,"TIMEOUT",StringFormat("quá %dh, chốt theo giá đóng cửa",InpJournalMaxHoldHours));
     }
  }

int JnlFindSetup(const string id)
  {
   int n=ArraySize(g_setups);
   for(int i=0;i<n;i++)
      if(g_setups[i].id==id)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| Cập nhật mỗi chu kỳ quét: xử lý các nến M1 mới đóng               |
//+------------------------------------------------------------------+
void JnlUpdate(const datetime now)
  {
   if(!InpJournalEnabled)
      return;
   JnlRollDay();
   datetime curMinute=(datetime)((long)now-((long)now%60));
   int n=ArraySize(g_jnl);
   for(int i=0;i<n;i++)
     {
      if(g_jnl[i].phase==JP_CLOSED)
         continue;
      string sym=g_jnl[i].sym;
      if(!(bool)SymbolInfoInteger(sym,SYMBOL_SELECT) && SymbolSelect(sym,true))
        {
         int ui=UniFind(sym);
         if(ui>=0 && !g_uni[ui].selectedByEA)
           {
            g_uni[ui].selectedByEA=true;
            g_uni[ui].selectedAt=TimeTradeServer();
           }
        }

      //--- lúc chờ khớp: không xét nến sau thời điểm setup đã đóng
      datetime waitLimit=0;
      int si=JnlFindSetup(g_jnl[i].id);
      bool setupClosed=(si<0 || !SigIsOpenState(g_setups[si].state));
      if(g_jnl[i].phase==JP_WAIT && setupClosed)
        {
         if(si>=0 && g_setups[si].closedAt>0)
            waitLimit=g_setups[si].closedAt;
         else
            waitLimit=(datetime)((long)g_jnl[i].createdAt+(long)InpSetupExpiryHours*3600);
        }

      datetime from=(datetime)((long)g_jnl[i].lastBar+60);
      if((long)curMinute-(long)from>(long)JNL_MAX_BARS*60)
        {
         from=(datetime)((long)curMinute-(long)JNL_MAX_BARS*60);
         g_jnl[i].note="thiếu dữ liệu M1 một đoạn (EA tắt lâu)";
        }
      bool waitDone=(g_jnl[i].phase==JP_WAIT && waitLimit>0 && from>=waitLimit);
      if(from<curMinute && !waitDone)
        {
         MqlRates r[];
         int got=CopyRates(sym,PERIOD_M1,from,curMinute,r);
         if(got<0)
           {
            LogD(StringFormat("[JOURNAL] %s: chưa tải được nến M1 (lỗi %d)",sym,GetLastError()));
            continue;
           }
         for(int k=0;k<got;k++)
           {
            if(r[k].time<=g_jnl[i].lastBar || r[k].time>=curMinute)
               continue;
            if(g_jnl[i].phase==JP_WAIT && waitLimit>0 && r[k].time>=waitLimit)
               break;
            JnlApplyBar(i,r[k]);
            g_jnl[i].lastBar=r[k].time;
            g_jnlDirty=true;
            if(g_jnl[i].phase==JP_CLOSED)
               break;
           }
        }
      //--- setup đã đóng mà giá chưa tới entry_ref -> không khớp
      if(g_jnl[i].phase==JP_WAIT && setupClosed)
        {
         string why=(si>=0) ? "setup "+SigStateName(g_setups[si].state) : "setup không còn theo dõi";
         JnlFinish(i,(si>=0 && g_setups[si].closedAt>0) ? g_setups[si].closedAt : now,"NOT_FILLED",why);
        }
     }
   //--- bỏ bản ghi đã đóng (đã ghi CSV)
   int w=0;
   for(int i=0;i<n;i++)
     {
      if(g_jnl[i].phase==JP_CLOSED)
         continue;
      if(w!=i)
         JnlCopy(g_jnl[w],g_jnl[i]);
      w++;
     }
   if(w!=n)
      ArrayResize(g_jnl,w);
  }

//+------------------------------------------------------------------+
//| Lưu / nạp bản ghi đang mở + thống kê                              |
//+------------------------------------------------------------------+
bool JnlSave()
  {
   if(!g_jnlLoaded || g_jnlStateFile=="")
      return false;
   string tmp=g_jnlStateFile+".tmp";
   int h=FileOpen(tmp,FILE_WRITE|FILE_TXT|FILE_UNICODE);
   if(h==INVALID_HANDLE)
     {
      LogE(StringFormat("[JOURNAL] Không ghi được %s (lỗi %d).",tmp,GetLastError()));
      return false;
     }
   FileWriteString(h,StringFormat("H|1|%d|%d|%d|%d|%s|%s|%s|%s|%d|%d|%s\r\n",g_jsClosed,g_jsFilled,g_jsWinA,g_jsWinB,
                                  StateD(g_jsSumA),StateD(g_jsSumB),StateD(g_jsSumC),StateD(g_jsMoneyA),
                                  g_jdKey,g_jdClosed,StateD(g_jdSumA)));
   int n=ArraySize(g_jnl);
   for(int i=0;i<n;i++)
     {
      if(g_jnl[i].phase==JP_CLOSED)
         continue;
      string line="J|"+StateClean(g_jnl[i].id)+"|"+StateClean(g_jnl[i].sym)+"|"+IntegerToString(g_jnl[i].tier)+"|"+
                  IntegerToString(g_jnl[i].assetGroup)+"|"+IntegerToString(g_jnl[i].side)+"|"+IntegerToString(g_jnl[i].type)+"|"+
                  IntegerToString(g_jnl[i].score)+"|"+IntegerToString(g_jnl[i].maxScore)+"|"+(g_jnl[i].pending ? "1" : "0")+"|"+
                  (g_jnl[i].riskWarn ? "1" : "0")+"|"+StateD(g_jnl[i].entry)+"|"+StateD(g_jnl[i].sl)+"|"+
                  StateD(g_jnl[i].tp1)+"|"+StateD(g_jnl[i].tp2)+"|"+StateD(g_jnl[i].rr1)+"|"+StateD(g_jnl[i].rr2)+"|"+
                  StateD(g_jnl[i].spread)+"|"+StateD(g_jnl[i].lots)+"|"+StateD(g_jnl[i].riskMoney)+"|"+
                  StateD(g_jnl[i].riskPct)+"|"+StateT(g_jnl[i].createdAt)+"|"+StateT(g_jnl[i].lastBar)+"|"+
                  StateT(g_jnl[i].fillTime)+"|"+IntegerToString(g_jnl[i].phase)+"|"+StateD(g_jnl[i].rA)+"|"+
                  StateD(g_jnl[i].rB)+"|"+StateD(g_jnl[i].rC1)+"|"+StateD(g_jnl[i].rC2)+"|"+
                  (g_jnl[i].c2Active ? "1" : "0")+"|"+StateD(g_jnl[i].mfe)+"|"+StateD(g_jnl[i].mae)+"|"+
                  StateClean(g_jnl[i].note);
      FileWriteString(h,line+"\r\n");
     }
   FileClose(h);
   if(!FileMove(tmp,0,g_jnlStateFile,FILE_REWRITE))
     {
      LogE(StringFormat("[JOURNAL] Không đổi tên %s (lỗi %d).",tmp,GetLastError()));
      return false;
     }
   g_jnlDirty=false;
   return true;
  }

void JnlLoad()
  {
   g_jnlStateFile=JnlFileBase()+"_open.txt";
   g_jnlLoaded=true;
   ArrayResize(g_jnl,0);
   g_jsClosed=0;
   g_jsFilled=0;
   g_jsWinA=0;
   g_jsWinB=0;
   g_jsSumA=0.0;
   g_jsSumB=0.0;
   g_jsSumC=0.0;
   g_jsMoneyA=0.0;
   g_jdKey=0;
   g_jdClosed=0;
   g_jdSumA=0.0;
   if(!FileIsExist(g_jnlStateFile))
      return;
   int h=FileOpen(g_jnlStateFile,FILE_READ|FILE_TXT|FILE_UNICODE|FILE_SHARE_READ);
   if(h==INVALID_HANDLE)
     {
      LogE(StringFormat("[JOURNAL] Không đọc được %s (lỗi %d) - KHÔNG ghi đè file cũ.",g_jnlStateFile,GetLastError()));
      g_jnlLoaded=false;
      return;
     }
   int loaded=0,bad=0;
   while(!FileIsEnding(h))
     {
      string line=StrTrim(FileReadString(h));
      if(line=="")
         continue;
      string f[];
      int k=StringSplit(line,'|',f);
      if(k>=13 && f[0]=="H" && f[1]=="1")
        {
         g_jsClosed=(int)StringToInteger(f[2]);
         g_jsFilled=(int)StringToInteger(f[3]);
         g_jsWinA=(int)StringToInteger(f[4]);
         g_jsWinB=(int)StringToInteger(f[5]);
         g_jsSumA=StateParseD(f[6]);
         g_jsSumB=StateParseD(f[7]);
         g_jsSumC=StateParseD(f[8]);
         g_jsMoneyA=StateParseD(f[9]);
         g_jdKey=(int)StringToInteger(f[10]);
         g_jdClosed=(int)StringToInteger(f[11]);
         g_jdSumA=StateParseD(f[12]);
         continue;
        }
      if(k<33 || f[0]!="J")
        {
         bad++;
         continue;
        }
      int n=ArraySize(g_jnl);
      ArrayResize(g_jnl,n+1,16);
      g_jnl[n].id=StateS(f[1]);
      g_jnl[n].sym=StateS(f[2]);
      g_jnl[n].tier=(int)StringToInteger(f[3]);
      g_jnl[n].assetGroup=(int)StringToInteger(f[4]);
      g_jnl[n].side=(int)StringToInteger(f[5]);
      g_jnl[n].type=(int)StringToInteger(f[6]);
      g_jnl[n].score=(int)StringToInteger(f[7]);
      g_jnl[n].maxScore=(int)StringToInteger(f[8]);
      g_jnl[n].pending=(f[9]=="1");
      g_jnl[n].riskWarn=(f[10]=="1");
      g_jnl[n].entry=StateParseD(f[11]);
      g_jnl[n].sl=StateParseD(f[12]);
      g_jnl[n].tp1=StateParseD(f[13]);
      g_jnl[n].tp2=StateParseD(f[14]);
      g_jnl[n].rr1=StateParseD(f[15]);
      g_jnl[n].rr2=StateParseD(f[16]);
      g_jnl[n].spread=StateParseD(f[17]);
      g_jnl[n].lots=StateParseD(f[18]);
      g_jnl[n].riskMoney=StateParseD(f[19]);
      g_jnl[n].riskPct=StateParseD(f[20]);
      g_jnl[n].createdAt=(datetime)StringToInteger(f[21]);
      g_jnl[n].lastBar=(datetime)StringToInteger(f[22]);
      g_jnl[n].fillTime=(datetime)StringToInteger(f[23]);
      g_jnl[n].closeTime=0;
      g_jnl[n].phase=(int)StringToInteger(f[24]);
      g_jnl[n].rA=StateParseD(f[25]);
      g_jnl[n].rB=StateParseD(f[26]);
      g_jnl[n].rC1=StateParseD(f[27]);
      g_jnl[n].rC2=StateParseD(f[28]);
      g_jnl[n].c2Active=(f[29]=="1");
      g_jnl[n].mfe=StateParseD(f[30]);
      g_jnl[n].mae=StateParseD(f[31]);
      g_jnl[n].note=StateS(f[32]);
      g_jnl[n].outcome="";
      if(g_jnl[n].phase!=JP_WAIT && g_jnl[n].phase!=JP_TRADE)
        {
         ArrayResize(g_jnl,n);
         bad++;
         continue;
        }
      loaded++;
     }
   FileClose(h);
   if(bad>0)
      LogW(StringFormat("[JOURNAL] Bỏ qua %d dòng lỗi trong %s.",bad,g_jnlStateFile));
   LogI(StringFormat("[JOURNAL] Nạp %d kèo đang theo dõi; tích lũy %d kèo đã đóng.",loaded,g_jsClosed));
   g_jnlDirty=false;
  }

//+------------------------------------------------------------------+
//| Văn bản tóm tắt (tóm tắt cuối ngày + bảng trạng thái)            |
//+------------------------------------------------------------------+
string JnlSummaryText()
  {
   if(!InpJournalEnabled)
      return "";
   int waiting=0,trading=0;
   JnlOpenCount(waiting,trading);
   string s=StringFormat("Nhật ký (tín hiệu thật, tích lũy): %d kèo đã đóng | khớp %d",g_jsClosed,g_jsFilled);
   if(g_jsClosed>0)
      s+=StringFormat(" (%.0f%%)",100.0*g_jsFilled/g_jsClosed);
   if(g_jsFilled>0)
     {
      s+=StringFormat("\nA (TP1): thắng %d/%d (%.0f%%), tổng %+.2fR, TB %+.2fR/kèo, ≈ %s",g_jsWinA,g_jsFilled,
                      100.0*g_jsWinA/g_jsFilled,g_jsSumA,g_jsSumA/g_jsFilled,FmtMoney(g_jsMoneyA));
      s+=StringFormat("\nB (TP2): thắng %d/%d, tổng %+.2fR | C (50/50 + hòa vốn): tổng %+.2fR",
                      g_jsWinB,g_jsFilled,g_jsSumB,g_jsSumC);
      if(g_jsFilled<30)
         s+="\n(Mẫu còn nhỏ, chưa đủ để kết luận hiệu quả.)";
     }
   s+=StringFormat("\nHôm nay đóng %d kèo (A %+.2fR) | đang theo dõi: chờ khớp %d, đang chạy %d",
                   g_jdClosed,g_jdSumA,waiting,trading);
   return s;
  }

#endif
