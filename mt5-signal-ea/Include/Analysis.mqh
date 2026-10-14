//+------------------------------------------------------------------+
//| Analysis.mqh - chấm điểm bias, tìm swing, vùng Entry, SL/TP/RR    |
//| Chỉ tính toán trên dữ liệu đã đóng (shift >= 1).                  |
//| Include SAU khai báo input.                                      |
//+------------------------------------------------------------------+
#ifndef SIGNALEA_ANALYSIS_MQH
#define SIGNALEA_ANALYSIS_MQH

#include "Common.mqh"
#include "Indicators.mqh"

#define SIDE_BUY        1
#define SIDE_SELL      -1
#define STYPE_PULLBACK  0
#define STYPE_BREAKOUT  1

struct SwingPt
  {
   double            price;
   datetime          time;
   int               shift;
  };

struct LevelPt
  {
   double            price;
   string            kind;     // tên yếu tố, dùng để đếm số yếu tố khác nhau
  };

// Hình học của một setup (struct đơn giản, copy được)
struct SetupGeom
  {
   int               type;
   int               side;
   double            entryLow;
   double            entryHigh;
   double            entryRef;   // giá tham chiếu tính RR/lot (giữa vùng)
   double            sl;
   double            tp1;
   double            tp2;        // EMPTY_VALUE nếu không có
   double            rr1;
   double            rr2;
   int               confluence;
  };

// Kết quả phân tích 1 symbol
struct AnaResult
  {
   int               biasTf[TFI_COUNT];
   int               score;      // có dấu: + tăng, - giảm
   int               maxScore;
   bool              hasSetup;
   SetupGeom         geom;
   string            reasons;    // "hội tụ SMA50 H4 + Swing H1"
   string            note;       // lý do không có setup
  };

string SideName(const int side)       { return (side>0) ? "BUY" : "SELL"; }
string SideNameVi(const int side)     { return (side>0) ? "mua" : "bán"; }
string SetupTypeName(const int type)  { return (type==STYPE_BREAKOUT) ? "phá vỡ" : "chờ hồi"; }
string SetupTypeCode(const int type)  { return (type==STYPE_BREAKOUT) ? "BO" : "PB"; }

void AnaResetGeom(SetupGeom &g)
  {
   g.type=STYPE_PULLBACK;
   g.side=0;
   g.entryLow=0.0;
   g.entryHigh=0.0;
   g.entryRef=0.0;
   g.sl=0.0;
   g.tp1=0.0;
   g.tp2=EMPTY_VALUE;
   g.rr1=0.0;
   g.rr2=EMPTY_VALUE;
   g.confluence=0;
  }

//+------------------------------------------------------------------+
//| Bias                                                             |
//+------------------------------------------------------------------+
int AnaWeight(const int tfi)
  {
   switch(tfi)
     {
      case TFI_MN1: return InpWeightMN1;
      case TFI_W1:  return InpWeightW1;
      case TFI_D1:  return InpWeightD1;
      case TFI_H4:  return InpWeightH4;
      default:      return InpWeightH1;
     }
  }

// +1 / -1 khi đạt >= InpBiasMinConditions trong 4 điều kiện:
// close vs SMA base, close vs SMA mid, độ dốc SMA base, RSI vs 50
int AnaTfBias(const TfSnapshot &s)
  {
   if(s.bars<=0 || s.close==EMPTY_VALUE)
      return 0;
   int bull=0,bear=0;
   if(s.smaBase!=EMPTY_VALUE)
     {
      if(s.close>s.smaBase) bull++;
      else if(s.close<s.smaBase) bear++;
     }
   if(s.smaMid!=EMPTY_VALUE)
     {
      if(s.close>s.smaMid) bull++;
      else if(s.close<s.smaMid) bear++;
     }
   if(s.smaBase!=EMPTY_VALUE && s.smaBasePrev!=EMPTY_VALUE)
     {
      if(s.smaBase>s.smaBasePrev) bull++;
      else if(s.smaBase<s.smaBasePrev) bear++;
     }
   if(s.rsi!=EMPTY_VALUE)
     {
      if(s.rsi>50.0) bull++;
      else if(s.rsi<50.0) bear++;
     }
   if(bull>=InpBiasMinConditions)
      return 1;
   if(bear>=InpBiasMinConditions)
      return -1;
   return 0;
  }

void AnaBias(const TfSnapshot &snap[],AnaResult &res)
  {
   res.score=0;
   res.maxScore=0;
   for(int t=0;t<TFI_COUNT;t++)
     {
      res.biasTf[t]=AnaTfBias(snap[t]);
      res.score+=res.biasTf[t]*AnaWeight(t);
      res.maxScore+=AnaWeight(t);
     }
  }

// "MN1 0 | W1 0 | D1 giảm | H4 giảm | H1 giảm  (điểm 6/9)"
string AnaBiasText(const AnaResult &res)
  {
   string s="";
   for(int t=0;t<TFI_COUNT;t++)
     {
      string v=(res.biasTf[t]>0) ? "tăng" : ((res.biasTf[t]<0) ? "giảm" : "0");
      s+=(t>0 ? " | " : "")+TfName(g_tfList[t])+" "+v;
     }
   s+=StringFormat("  (điểm %d/%d)",IntAbs(res.score),res.maxScore);
   return s;
  }

//+------------------------------------------------------------------+
//| Swing (fractal): đỉnh cao hơn "strength" nến mỗi bên             |
//| Kết quả sắp xếp gần nhất trước. minShift để loại swing quá mới.  |
//+------------------------------------------------------------------+
int AnaSwings(const MqlRates &r[],const int n,const int strength,const int lookback,const bool highs,
              const int minShift,SwingPt &out[])
  {
   ArrayResize(out,0);
   if(strength<1 || n<2*strength+3)
      return 0;
   int first=IntMax(strength+1,minShift);
   int last=IntMin(lookback,n-strength-1);
   int cnt=0;
   for(int i=first;i<=last;i++)
     {
      double v=highs ? r[i].high : r[i].low;
      bool ok=true;
      for(int k=1;k<=strength && ok;k++)
        {
         double older=highs ? r[i+k].high : r[i+k].low;
         double newer=highs ? r[i-k].high : r[i-k].low;
         if(highs)
           {
            if(!(v>older && v>=newer))
               ok=false;
           }
         else
           {
            if(!(v<older && v<=newer))
               ok=false;
           }
        }
      if(!ok)
         continue;
      ArrayResize(out,cnt+1,32);
      out[cnt].price=v;
      out[cnt].time=r[i].time;
      out[cnt].shift=i;
      cnt++;
     }
   return cnt;
  }

//+------------------------------------------------------------------+
//| Tiện ích mức giá                                                 |
//+------------------------------------------------------------------+
void AnaAddLevel(LevelPt &arr[],const double price,const string kind)
  {
   if(price==EMPTY_VALUE || price<=0.0)
      return;
   int n=ArraySize(arr);
   ArrayResize(arr,n+1,32);
   arr[n].price=price;
   arr[n].kind=kind;
  }

void AnaAddSwingLevels(LevelPt &arr[],const SwingPt &sw[],const string kind)
  {
   int n=ArraySize(sw);
   for(int i=0;i<n;i++)
      AnaAddLevel(arr,sw[i].price,kind);
  }

// Sắp xếp mức theo khoảng cách tới ref (gần trước) - insertion sort, mảng nhỏ
void AnaSortByDistance(LevelPt &arr[],const double ref)
  {
   int n=ArraySize(arr);
   for(int i=1;i<n;i++)
     {
      double p=arr[i].price;
      string k=arr[i].kind;
      double d=MathAbs(p-ref);
      int j=i-1;
      while(j>=0 && MathAbs(arr[j].price-ref)>d)
        {
         arr[j+1].price=arr[j].price;
         arr[j+1].kind=arr[j].kind;
         j--;
        }
      arr[j+1].price=p;
      arr[j+1].kind=k;
     }
  }

//+------------------------------------------------------------------+
//| SL: ngoài swing gần nhất phía bảo vệ + buffer x ATR(H4)          |
//+------------------------------------------------------------------+
double AnaStopLoss(const int side,const double zoneLow,const double zoneHigh,
                   const SwingPt &a[],const SwingPt &b[],const double atrH4)
  {
   double found=EMPTY_VALUE;
   double limit=3.0*atrH4;
   for(int pass=0;pass<2;pass++)
     {
      int n=(pass==0) ? ArraySize(a) : ArraySize(b);
      for(int i=0;i<n;i++)
        {
         double p=(pass==0) ? a[i].price : b[i].price;
         if(side<0)
           {
            // swing high >= đáy vùng, gần nhất phía trên
            if(p>=zoneLow && p<=zoneHigh+limit && (found==EMPTY_VALUE || p<found))
               found=p;
           }
         else
           {
            if(p<=zoneHigh && p>=zoneLow-limit && (found==EMPTY_VALUE || p>found))
               found=p;
           }
        }
     }
   if(side<0)
     {
      if(found==EMPTY_VALUE)
         return zoneHigh+InpSlFallbackAtrH4*atrH4;
      return MathMax(found,zoneHigh)+InpSlBufferAtrH4*atrH4;
     }
   if(found==EMPTY_VALUE)
      return zoneLow-InpSlFallbackAtrH4*atrH4;
   return MathMin(found,zoneLow)-InpSlBufferAtrH4*atrH4;
  }

//+------------------------------------------------------------------+
//| TP1/TP2: hỗ trợ/kháng cự kế tiếp theo swing H4/D1                |
//+------------------------------------------------------------------+
bool AnaTargets(const int side,const double entryRef,const SwingPt &a[],const SwingPt &b[],
                const double atrH4,double &tp1,double &tp2)
  {
   tp1=EMPTY_VALUE;
   tp2=EMPTY_VALUE;
   double gap=InpTpMinGapAtrH4*atrH4;
   double dedup=0.25*atrH4;
   double c[];
   int cnt=0;
   for(int pass=0;pass<2;pass++)
     {
      int n=(pass==0) ? ArraySize(a) : ArraySize(b);
      for(int i=0;i<n;i++)
        {
         double p=(pass==0) ? a[i].price : b[i].price;
         bool ok=(side<0) ? (p<entryRef-gap) : (p>entryRef+gap);
         if(!ok)
            continue;
         ArrayResize(c,cnt+1,32);
         c[cnt]=p;
         cnt++;
        }
     }
   if(cnt==0)
      return false;
   // gần entry trước
   for(int i=1;i<cnt;i++)
     {
      double v=c[i];
      int j=i-1;
      while(j>=0 && MathAbs(c[j]-entryRef)>MathAbs(v-entryRef))
        {
         c[j+1]=c[j];
         j--;
        }
      c[j+1]=v;
     }
   tp1=c[0];
   for(int i=1;i<cnt;i++)
     {
      if(MathAbs(c[i]-tp1)>=dedup)
        {
         tp2=c[i];
         break;
        }
     }
   return true;
  }

// Tính SL/TP/RR, kiểm tra RR tối thiểu
bool AnaFinalizeGeom(SetupGeom &g,const SwingPt &slA[],const SwingPt &slB[],
                     const SwingPt &tpA[],const SwingPt &tpB[],const double atrH4,const double minRR,string &why)
  {
   g.sl=AnaStopLoss(g.side,g.entryLow,g.entryHigh,slA,slB,atrH4);
   double risk=(g.side<0) ? g.sl-g.entryRef : g.entryRef-g.sl;
   if(risk<=0.0)
     {
      why="SL không hợp lệ";
      return false;
     }
   if(!AnaTargets(g.side,g.entryRef,tpA,tpB,atrH4,g.tp1,g.tp2))
     {
      why="không tìm được mức TP (swing H4/D1)";
      return false;
     }
   g.rr1=MathAbs(g.tp1-g.entryRef)/risk;
   g.rr2=(g.tp2==EMPTY_VALUE) ? EMPTY_VALUE : MathAbs(g.tp2-g.entryRef)/risk;
   if(g.rr1<minRR)
     {
      why=StringFormat("RR TP1 %.2f < %.2f",g.rr1,minRR);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Setup chờ hồi: vùng hội tụ >= InpMinConfluence yếu tố            |
//+------------------------------------------------------------------+
bool AnaPullbackZone(const string sym,const int side,const TfSnapshot &snap[],
                     const SwingPt &swH1[],const SwingPt &swH4[],const double ref,
                     SetupGeom &g,string &reasons,string &why)
  {
   double atrH1=snap[TFI_H1].atr;
   double atrH4=snap[TFI_H4].atr;
   double w=InpEntryZoneAtrH1*atrH1;
   double tol=InpConfluenceTolAtrH1*atrH1;
   double maxDist=InpMaxEntryDistAtrH4*atrH4;

   LevelPt all[];
   AnaAddLevel(all,snap[TFI_H4].smaMid,"SMA"+IntegerToString(InpSmaMid)+" H4");
   AnaAddLevel(all,snap[TFI_H1].smaSlow,"SMA"+IntegerToString(InpSmaSlow)+" H1");
   AnaAddLevel(all,snap[TFI_H1].smaMid,"SMA"+IntegerToString(InpSmaMid)+" H1");
   AnaAddSwingLevels(all,swH1,"swing H1");
   AnaAddSwingLevels(all,swH4,"swing H4");

   // chỉ giữ mức đúng phía và trong phạm vi
   LevelPt lv[];
   int n=ArraySize(all);
   for(int i=0;i<n;i++)
     {
      double p=all[i].price;
      bool ok=(side<0) ? (p>ref+w*0.5 && p<=ref+maxDist) : (p<ref-w*0.5 && p>=ref-maxDist);
      if(ok)
         AnaAddLevel(lv,p,all[i].kind);
     }
   int m=ArraySize(lv);
   if(m<InpMinConfluence)
     {
      why=StringFormat("không đủ mức giá phía %s trong %.1f ATR(H4)",(side<0) ? "trên" : "dưới",InpMaxEntryDistAtrH4);
      return false;
     }
   AnaSortByDistance(lv,ref);

   for(int a=0;a<m;a++)
     {
      string kinds[];
      ArrayResize(kinds,0);
      double sum=0.0;
      int members=0;
      for(int j=0;j<m;j++)
        {
         double d=(side<0) ? lv[j].price-lv[a].price : lv[a].price-lv[j].price;
         if(d<0.0 || d>tol)
            continue;
         sum+=lv[j].price;
         members++;
         if(!StrInArray(lv[j].kind,kinds))
            StrArrayPush(kinds,lv[j].kind);
        }
      int k=ArraySize(kinds);
      if(k<InpMinConfluence)
         continue;
      double center=sum/members;
      double lo=center-w*0.5;
      double hi=center+w*0.5;
      if(side<0 && lo<=ref)
         continue;
      if(side>0 && hi>=ref)
         continue;
      g.type=STYPE_PULLBACK;
      g.side=side;
      g.entryLow=lo;
      g.entryHigh=hi;
      g.entryRef=center;
      g.confluence=k;
      reasons="hội tụ ";
      for(int q=0;q<k;q++)
         reasons+=(q>0 ? " + " : "")+kinds[q];
      return true;
     }
   why=StringFormat("không có vùng hội tụ >= %d yếu tố",InpMinConfluence);
   return false;
  }

//+------------------------------------------------------------------+
//| Setup phá vỡ: H4 vừa đóng vượt swing H4 gần nhất                 |
//+------------------------------------------------------------------+
bool AnaBreakoutZone(const string sym,const int side,const MqlRates &h4[],const int nH4,const TfSnapshot &snap[],
                     SetupGeom &g,string &reasons,string &why)
  {
   if(nH4<10)
     {
      why="thiếu nến H4";
      return false;
     }
   int st=InpSwingStrengthH4;
   SwingPt sw[];
   // swing phải hình thành trước nến phá vỡ (shift 1)
   if(AnaSwings(h4,nH4,st,InpSwingLookback,side>0,st+2,sw)==0)
     {
      why="không có swing H4";
      return false;
     }
   double level=sw[0].price;
   double c1=h4[1].close;
   double c2=h4[2].close;
   bool broke=(side<0) ? (c1<level && c2>=level) : (c1>level && c2<=level);
   if(!broke)
     {
      why="H4 chưa phá swing gần nhất";
      return false;
     }
   double atrH4=snap[TFI_H4].atr;
   double w=MathMax(InpEntryZoneAtrH1*snap[TFI_H1].atr,SymbolInfoDouble(sym,SYMBOL_POINT));
   double lo,hi;
   if(side<0)
     {
      lo=c1;
      hi=MathMin(level,c1+0.5*atrH4);
      if(hi-lo<w)
         hi=lo+w;
     }
   else
     {
      hi=c1;
      lo=MathMax(level,c1-0.5*atrH4);
      if(hi-lo<w)
         lo=hi-w;
     }
   g.type=STYPE_BREAKOUT;
   g.side=side;
   g.entryLow=lo;
   g.entryHigh=hi;
   g.entryRef=(lo+hi)*0.5;
   g.confluence=1;
   int dg=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   reasons=StringFormat("H4 đóng %s %s swing H4 %s",DoubleToString(c1,dg),
                        (side<0) ? "dưới đáy" : "trên đỉnh",DoubleToString(level,dg));
   return true;
  }

//+------------------------------------------------------------------+
//| Phân tích đầy đủ 1 symbol                                        |
//| allowSetup=false: chỉ tính bias (symbol đang có setup/cooldown)  |
//+------------------------------------------------------------------+
bool AnaAnalyze(const string sym,const ENUM_SYMBOL_TIER tier,
                const MqlRates &h4[],const int nH4,const MqlRates &h1[],const int nH1,
                const MqlRates &d1[],const int nD1,const TfSnapshot &snap[],
                const bool newH4,const bool allowSetup,AnaResult &res)
  {
   res.hasSetup=false;
   res.reasons="";
   res.note="";
   AnaResetGeom(res.geom);
   AnaBias(snap,res);
   if(!allowSetup)
     {
      res.note="đang có setup/cooldown";
      return false;
     }
   int minScore=(tier==TIER_PRIORITY) ? InpMinScorePriority : InpMinScoreOther;
   double minRR=(tier==TIER_PRIORITY) ? InpMinRRPriority : InpMinRROther;
   if(IntAbs(res.score)<minScore)
     {
      res.note=StringFormat("bias %d/%d chưa đạt ngưỡng %d",IntAbs(res.score),res.maxScore,minScore);
      return false;
     }
   int side=(res.score>0) ? SIDE_BUY : SIDE_SELL;
   double atrH4=snap[TFI_H4].atr;

   //--- swing
   SwingPt h1Hi[],h1Lo[],h4Hi[],h4Lo[],d1Hi[],d1Lo[];
   AnaSwings(h1,nH1,InpSwingStrengthH1,InpSwingLookback,true,1,h1Hi);
   AnaSwings(h1,nH1,InpSwingStrengthH1,InpSwingLookback,false,1,h1Lo);
   AnaSwings(h4,nH4,InpSwingStrengthH4,InpSwingLookback,true,1,h4Hi);
   AnaSwings(h4,nH4,InpSwingStrengthH4,InpSwingLookback,false,1,h4Lo);
   AnaSwings(d1,nD1,InpSwingStrengthD1,InpSwingLookback,true,1,d1Hi);
   AnaSwings(d1,nD1,InpSwingStrengthD1,InpSwingLookback,false,1,d1Lo);

   double bid=SymbolInfoDouble(sym,SYMBOL_BID);
   double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
   double ref=(side<0) ? bid : ask;

   SetupGeom pb,bo;
   AnaResetGeom(pb);
   AnaResetGeom(bo);
   string pbReasons="",boReasons="",pbWhy="",boWhy="";
   bool pbOk=false,boOk=false;

   //--- chờ hồi
   if(InpEnablePullback)
     {
      bool zone=(side<0) ? AnaPullbackZone(sym,side,snap,h1Hi,h4Hi,ref,pb,pbReasons,pbWhy)
                         : AnaPullbackZone(sym,side,snap,h1Lo,h4Lo,ref,pb,pbReasons,pbWhy);
      if(zone)
        {
         if(side<0)
            pbOk=AnaFinalizeGeom(pb,h1Hi,h4Hi,h4Lo,d1Lo,atrH4,minRR,pbWhy);
         else
            pbOk=AnaFinalizeGeom(pb,h1Lo,h4Lo,h4Hi,d1Hi,atrH4,minRR,pbWhy);
        }
     }
   //--- phá vỡ (chỉ khi có nến H4 mới đóng)
   if(InpEnableBreakout && newH4)
     {
      if(AnaBreakoutZone(sym,side,h4,nH4,snap,bo,boReasons,boWhy))
        {
         if(side<0)
            boOk=AnaFinalizeGeom(bo,h1Hi,h4Hi,h4Lo,d1Lo,atrH4,minRR,boWhy);
         else
            boOk=AnaFinalizeGeom(bo,h1Lo,h4Lo,h4Hi,d1Hi,atrH4,minRR,boWhy);
        }
     }
   else if(InpEnableBreakout)
      boWhy="chưa có nến H4 mới";

   if(!pbOk && !boOk)
     {
      res.note="chờ hồi: "+(pbWhy=="" ? "tắt" : pbWhy)+" | phá vỡ: "+(boWhy=="" ? "tắt" : boWhy);
      return false;
     }
   bool useBo=(boOk && (!pbOk || bo.rr1>pb.rr1));
   if(useBo)
     {
      res.geom=bo;
      res.reasons=boReasons;
     }
   else
     {
      res.geom=pb;
      res.reasons=pbReasons;
     }
   res.hasSetup=true;
   return true;
  }

#endif
