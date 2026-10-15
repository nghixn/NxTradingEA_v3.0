//+------------------------------------------------------------------+
//| Levels.mqh - tìm và vẽ vùng hỗ trợ/kháng cự lên chart            |
//| Nguồn: swing (fractal) W1/D1/H4 đã xác nhận, gom thành vùng.     |
//| Điểm vùng = tổng trọng số các lần chạm: W1 3, D1 2, H4 1.        |
//| Chỉ vẽ đối tượng đồ họa, KHÔNG giao dịch.                        |
//| Include SAU Analysis.mqh (dùng AnaSwings) và khai báo input.     |
//+------------------------------------------------------------------+
#ifndef SIGNALEA_LEVELS_MQH
#define SIGNALEA_LEVELS_MQH

#include "Common.mqh"
#include "Indicators.mqh"
#include "Analysis.mqh"

#define LV_PREFIX        "SEA_LV_"
#define LV_W_W1          3
#define LV_W_D1          2
#define LV_W_H4          1
#define LV_LOOKBACK_W1   156     // ~3 năm
#define LV_LOOKBACK_D1   250     // ~1 năm
#define LV_LOOKBACK_H4   300     // ~2 tháng
#define LV_SWING_W1      2
#define LV_MAX_CALC      2       // số symbol tính lại tối đa mỗi chu kỳ (VPS yếu)

// Một vùng hỗ trợ/kháng cự (vai trò xác định lúc vẽ theo giá hiện tại)
struct LvZone
  {
   string            sym;
   double            lo;
   double            hi;
   double            center;
   int               score;
   int               nW1;
   int               nD1;
   int               nH4;
   datetime          first;     // lần chạm cũ nhất
   datetime          last;      // lần chạm gần nhất
  };

// Trạng thái tính theo symbol
struct LvSym
  {
   string            sym;
   datetime          h1Bar;     // nến H1 đã đóng lúc tính gần nhất
   double            lastClose;
  };

LvZone   g_lvZ[];
LvSym    g_lvS[];
long     g_lvChart[];            // chart đã vẽ + chữ ký để khỏi vẽ lại khi không đổi
string   g_lvSig[];

//+------------------------------------------------------------------+
//| Tiện ích mảng                                                    |
//+------------------------------------------------------------------+
int LvSymIndex(const string sym)
  {
   int n=ArraySize(g_lvS);
   for(int i=0;i<n;i++)
      if(g_lvS[i].sym==sym)
         return i;
   return -1;
  }

void LvCopyZone(const int dst,const int src)
  {
   g_lvZ[dst].sym=g_lvZ[src].sym;
   g_lvZ[dst].lo=g_lvZ[src].lo;
   g_lvZ[dst].hi=g_lvZ[src].hi;
   g_lvZ[dst].center=g_lvZ[src].center;
   g_lvZ[dst].score=g_lvZ[src].score;
   g_lvZ[dst].nW1=g_lvZ[src].nW1;
   g_lvZ[dst].nD1=g_lvZ[src].nD1;
   g_lvZ[dst].nH4=g_lvZ[src].nH4;
   g_lvZ[dst].first=g_lvZ[src].first;
   g_lvZ[dst].last=g_lvZ[src].last;
  }

void LvRemoveSymbol(const string sym)
  {
   int n=ArraySize(g_lvZ);
   int k=0;
   for(int i=0;i<n;i++)
     {
      if(g_lvZ[i].sym==sym)
         continue;
      if(k!=i)
         LvCopyZone(k,i);
      k++;
     }
   ArrayResize(g_lvZ,k);
  }

void LvMarkDone(const string sym,const datetime h1Bar,const double lastClose)
  {
   int s=LvSymIndex(sym);
   if(s<0)
     {
      s=ArraySize(g_lvS);
      ArrayResize(g_lvS,s+1,16);
      g_lvS[s].sym=sym;
     }
   g_lvS[s].h1Bar=h1Bar;
   g_lvS[s].lastClose=lastClose;
  }

//+------------------------------------------------------------------+
//| Gom điểm swing                                                   |
//+------------------------------------------------------------------+
void LvAddPoints(const SwingPt &sw[],const int weight,double &pp[],int &pw[],datetime &pt[])
  {
   int n=ArraySize(sw);
   for(int i=0;i<n;i++)
     {
      int k=ArraySize(pp);
      ArrayResize(pp,k+1,64);
      ArrayResize(pw,k+1,64);
      ArrayResize(pt,k+1,64);
      pp[k]=sw[i].price;
      pw[k]=weight;
      pt[k]=sw[i].time;
     }
  }

void LvCollectTf(const MqlRates &r[],const int n,const int strength,const int lookback,const int weight,
                 double &pp[],int &pw[],datetime &pt[])
  {
   if(n<2*strength+3)
      return;
   SwingPt hi[],lo[];
   AnaSwings(r,n,strength,lookback,true,1,hi);
   AnaSwings(r,n,strength,lookback,false,1,lo);
   LvAddPoints(hi,weight,pp,pw,pt);
   LvAddPoints(lo,weight,pp,pw,pt);
  }

// Sắp xếp tăng dần theo giá (insertion sort, vài trăm điểm)
void LvSortPoints(double &pp[],int &pw[],datetime &pt[])
  {
   int n=ArraySize(pp);
   for(int i=1;i<n;i++)
     {
      double p=pp[i];
      int w=pw[i];
      datetime t=pt[i];
      int j=i-1;
      while(j>=0 && pp[j]>p)
        {
         pp[j+1]=pp[j];
         pw[j+1]=pw[j];
         pt[j+1]=pt[j];
         j--;
        }
      pp[j+1]=p;
      pw[j+1]=w;
      pt[j+1]=t;
     }
  }

//+------------------------------------------------------------------+
//| Tính vùng cho 1 symbol. Trả về: 1 xong, 0 chờ dữ liệu, -1 lỗi    |
//+------------------------------------------------------------------+
int LvCompute(const string sym,const int barsToLoad,const datetime h1Bar)
  {
   MqlRates d1[],h4[],w1[];
   int nD1=IndLoadRates(sym,PERIOD_D1,barsToLoad,d1);
   int nH4=IndLoadRates(sym,PERIOD_H4,barsToLoad,h4);
   if(nD1==-2 || nH4==-2)
      return 0;
   if(nD1<30 || nH4<30)
      return -1;
   int nW1=IndLoadRates(sym,PERIOD_W1,barsToLoad,w1);

   double atrD1=IndATR(d1,nD1,InpAtrPeriod,1);
   double atrH4=IndATR(h4,nH4,InpAtrPeriod,1);
   if(atrD1==EMPTY_VALUE || atrH4==EMPTY_VALUE || atrD1<=0.0 || atrH4<=0.0)
      return -1;

   double pp[];
   int pw[];
   datetime pt[];
   if(InpLevelsUseW1 && nW1>0)
      LvCollectTf(w1,nW1,LV_SWING_W1,LV_LOOKBACK_W1,LV_W_W1,pp,pw,pt);
   LvCollectTf(d1,nD1,InpSwingStrengthD1,LV_LOOKBACK_D1,LV_W_D1,pp,pw,pt);
   LvCollectTf(h4,nH4,InpSwingStrengthH4,LV_LOOKBACK_H4,LV_W_H4,pp,pw,pt);
   LvSortPoints(pp,pw,pt);

   double ref=h4[1].close;
   double tol=InpLevelsClusterAtrH4*atrH4;
   double range=InpLevelsRangeAtrD1*atrD1;
   double minHalf=0.1*atrH4;

   LvRemoveSymbol(sym);
   int n=ArraySize(pp);
   int i=0;
   while(i<n)
     {
      // vùng = các điểm cách điểm thấp nhất của vùng <= tol (không nối chuỗi vô hạn)
      int j=i;
      double sumPW=0.0;
      int score=0,cW1=0,cD1=0,cH4=0;
      datetime tFirst=0,tLast=0;
      while(j<n && pp[j]-pp[i]<=tol)
        {
         sumPW+=pp[j]*pw[j];
         score+=pw[j];
         if(pw[j]==LV_W_W1)
            cW1++;
         else if(pw[j]==LV_W_D1)
            cD1++;
         else
            cH4++;
         if(tFirst==0 || pt[j]<tFirst)
            tFirst=pt[j];
         if(pt[j]>tLast)
            tLast=pt[j];
         j++;
        }
      double lo=pp[i];
      double hi=pp[j-1];
      double center=sumPW/score;
      i=j;
      if(score<InpLevelsMinScore || MathAbs(center-ref)>range)
         continue;
      // vùng quá mỏng: nới ra tối thiểu +/- 0.1 ATR(H4)
      if(center-lo<minHalf)
         lo=center-minHalf;
      if(hi-center<minHalf)
         hi=center+minHalf;
      int k=ArraySize(g_lvZ);
      ArrayResize(g_lvZ,k+1,64);
      g_lvZ[k].sym=sym;
      g_lvZ[k].lo=lo;
      g_lvZ[k].hi=hi;
      g_lvZ[k].center=center;
      g_lvZ[k].score=score;
      g_lvZ[k].nW1=cW1;
      g_lvZ[k].nD1=cD1;
      g_lvZ[k].nH4=cH4;
      g_lvZ[k].first=tFirst;
      g_lvZ[k].last=tLast;
     }

   LvMarkDone(sym,h1Bar,ref);
   return 1;
  }

//+------------------------------------------------------------------+
//| Chọn N vùng gần giá nhất mỗi phía                                |
//| side>0: kháng cự (tâm trên giá), side<0: hỗ trợ (tâm dưới giá)   |
//+------------------------------------------------------------------+
int LvSelect(const string sym,const double price,const int side,int &out[])
  {
   ArrayResize(out,0);
   int n=ArraySize(g_lvZ);
   int cnt=0;
   for(int i=0;i<n;i++)
     {
      if(g_lvZ[i].sym!=sym)
         continue;
      double d=g_lvZ[i].center-price;
      if((side>0 && d<=0.0) || (side<0 && d>=0.0))
         continue;
      // chèn theo khoảng cách tăng dần
      ArrayResize(out,cnt+1,16);
      int j=cnt-1;
      while(j>=0 && MathAbs(g_lvZ[out[j]].center-price)>MathAbs(d))
        {
         out[j+1]=out[j];
         j--;
        }
      out[j+1]=i;
      cnt++;
     }
   if(cnt>InpLevelsPerSide)
     {
      ArrayResize(out,InpLevelsPerSide);
      cnt=InpLevelsPerSide;
     }
   return cnt;
  }

string LvStrengthName(const int score)
  {
   if(score>=InpLevelsStrongScore)
      return "mạnh";
   if(score>=(InpLevelsStrongScore+InpLevelsMinScore)/2)
      return "TB";
   return "yếu";
  }

string LvTouchText(const int i)
  {
   string s="";
   if(g_lvZ[i].nW1>0)
      s+="W1x"+IntegerToString(g_lvZ[i].nW1);
   if(g_lvZ[i].nD1>0)
      s+=(s=="" ? "" : " ")+"D1x"+IntegerToString(g_lvZ[i].nD1);
   if(g_lvZ[i].nH4>0)
      s+=(s=="" ? "" : " ")+"H4x"+IntegerToString(g_lvZ[i].nH4);
   return s;
  }

double LvPrice(const string sym)
  {
   double bid=SymbolInfoDouble(sym,SYMBOL_BID);
   if(bid>0.0)
      return bid;
   int s=LvSymIndex(sym);
   return (s>=0) ? g_lvS[s].lastClose : 0.0;
  }

// "KC: 82700 (mạnh), 83900 (TB) | HT: 80100 (mạnh), 78000 (yếu)"
string LvSummaryText(const string sym)
  {
   double price=LvPrice(sym);
   if(price<=0.0)
      return "";
   int dg=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   string out="";
   for(int pass=0;pass<2;pass++)
     {
      int side=(pass==0) ? 1 : -1;
      int idx[];
      int cnt=LvSelect(sym,price,side,idx);
      string s="";
      for(int k=0;k<cnt;k++)
         s+=(k>0 ? ", " : "")+DoubleToString(g_lvZ[idx[k]].center,dg)+" ("+LvStrengthName(g_lvZ[idx[k]].score)+")";
      out+=(pass==0 ? "KC: " : " | HT: ")+(s=="" ? "-" : s);
     }
   return out;
  }

//+------------------------------------------------------------------+
//| Vẽ                                                               |
//+------------------------------------------------------------------+
void LvSetCommon(const long cid,const string name,const string tip)
  {
   ObjectSetInteger(cid,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(cid,name,OBJPROP_HIDDEN,true);
   ObjectSetString(cid,name,OBJPROP_TOOLTIP,tip);
  }

void LvDrawZone(const long cid,const string sym,const int i,const int side,const int k,
                const datetime tLabel,const datetime tRight,const double price)
  {
   int dg=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   bool res=(side>0);
   bool testing=(price>=g_lvZ[i].lo && price<=g_lvZ[i].hi);
   string role=res ? "Kháng cự" : "Hỗ trợ";
   string strength=LvStrengthName(g_lvZ[i].score);
   color lineClr=res ? InpLevelsColorRes : InpLevelsColorSup;
   color zoneClr=res ? InpLevelsZoneColorRes : InpLevelsZoneColorSup;
   string base=LV_PREFIX+(res ? "R" : "S")+IntegerToString(k);
   string tip=StringFormat("%s %s - %s | điểm %d (%s) | chạm: %s | gần nhất: %s%s",role,
                           DoubleToString(g_lvZ[i].lo,dg),DoubleToString(g_lvZ[i].hi,dg),g_lvZ[i].score,strength,
                           LvTouchText(i),FmtDisplayTime(g_lvZ[i].last),testing ? " | GIÁ ĐANG TEST" : "");

   if(InpLevelsDrawZones)
     {
      string zn=base+"_Z";
      if(ObjectCreate(cid,zn,OBJ_RECTANGLE,0,g_lvZ[i].first,g_lvZ[i].hi,tRight,g_lvZ[i].lo))
        {
         ObjectSetInteger(cid,zn,OBJPROP_COLOR,zoneClr);
         ObjectSetInteger(cid,zn,OBJPROP_FILL,true);
         ObjectSetInteger(cid,zn,OBJPROP_BACK,true);
         LvSetCommon(cid,zn,tip);
        }
     }
   string ln=base+"_L";
   if(ObjectCreate(cid,ln,OBJ_HLINE,0,0,g_lvZ[i].center))
     {
      int width=(strength=="mạnh") ? 3 : ((strength=="TB") ? 2 : 1);
      ObjectSetInteger(cid,ln,OBJPROP_COLOR,lineClr);
      ObjectSetInteger(cid,ln,OBJPROP_WIDTH,width);
      ObjectSetInteger(cid,ln,OBJPROP_STYLE,(width==1) ? STYLE_DASH : STYLE_SOLID);
      ObjectSetInteger(cid,ln,OBJPROP_BACK,true);
      LvSetCommon(cid,ln,tip);
     }
   if(InpLevelsShowLabels)
     {
      string tn=base+"_T";
      string text=StringFormat("%s %s · %s · %s",res ? "KC" : "HT",DoubleToString(g_lvZ[i].center,dg),
                               LvTouchText(i),strength);
      if(ObjectCreate(cid,tn,OBJ_TEXT,0,tLabel,g_lvZ[i].center))
        {
         ObjectSetString(cid,tn,OBJPROP_TEXT,text);
         ObjectSetString(cid,tn,OBJPROP_FONT,"Arial");
         ObjectSetInteger(cid,tn,OBJPROP_FONTSIZE,8);
         ObjectSetInteger(cid,tn,OBJPROP_COLOR,lineClr);
         ObjectSetInteger(cid,tn,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
         LvSetCommon(cid,tn,tip);
        }
     }
  }

// Vẽ lại 1 chart nếu có thay đổi (vùng, giá đổi phía, nến mới, đổi khung)
void LvDrawChart(const long cid,const string sym)
  {
   ENUM_TIMEFRAMES tf=ChartPeriod(cid);
   double price=LvPrice(sym);
   datetime bar0=iTime(sym,tf,0);
   if(price<=0.0 || bar0==0)
      return;
   int resIdx[],supIdx[];
   int nR=LvSelect(sym,price,1,resIdx);
   int nS=LvSelect(sym,price,-1,supIdx);

   string sig=sym+"|"+IntegerToString((int)tf)+"|"+IntegerToString((long)bar0);
   for(int k=0;k<nR;k++)
      sig+="|R"+DoubleToString(g_lvZ[resIdx[k]].center,8)+":"+IntegerToString(g_lvZ[resIdx[k]].score);
   for(int k=0;k<nS;k++)
      sig+="|S"+DoubleToString(g_lvZ[supIdx[k]].center,8)+":"+IntegerToString(g_lvZ[supIdx[k]].score);

   int slot=-1;
   int n=ArraySize(g_lvChart);
   for(int i=0;i<n;i++)
      if(g_lvChart[i]==cid)
        {
         slot=i;
         break;
        }
   // chữ ký giống lần trước và đối tượng còn trên chart (người dùng có thể đã xóa) -> bỏ qua
   if(slot>=0 && g_lvSig[slot]==sig && (nR+nS==0 || ObjectFind(cid,LV_PREFIX+(nR>0 ? "R0_L" : "S0_L"))>=0))
      return;

   ObjectsDeleteAll(cid,LV_PREFIX);
   int ps=PeriodSeconds(tf);
   datetime tLabel=(datetime)((long)bar0+2*(long)ps);
   datetime tRight=(datetime)((long)bar0+20*(long)ps);
   for(int k=0;k<nR;k++)
      LvDrawZone(cid,sym,resIdx[k],1,k,tLabel,tRight,price);
   for(int k=0;k<nS;k++)
      LvDrawZone(cid,sym,supIdx[k],-1,k,tLabel,tRight,price);
   ChartRedraw(cid);

   if(slot<0)
     {
      slot=n;
      ArrayResize(g_lvChart,n+1,16);
      ArrayResize(g_lvSig,n+1,16);
      g_lvChart[slot]=cid;
     }
   g_lvSig[slot]=sig;
  }

//+------------------------------------------------------------------+
//| Gọi mỗi chu kỳ quét: tính lại khi có nến H1 mới, vẽ lên mọi      |
//| chart đang mở của symbol đó (hoặc chỉ chart gắn EA)              |
//+------------------------------------------------------------------+
void LvUpdate(const int barsToLoad)
  {
   if(!InpLevelsEnabled)
      return;
   long charts[];
   int nc=0;
   bool allCharts=InpLevelsAllCharts && !(bool)MQLInfoInteger(MQL_TESTER);
   if(allCharts)
     {
      long cid=ChartFirst();
      while(cid>=0 && nc<100)
        {
         ArrayResize(charts,nc+1,16);
         charts[nc++]=cid;
         cid=ChartNext(cid);
        }
     }
   else
     {
      ArrayResize(charts,1);
      charts[0]=ChartID();
      nc=1;
     }

   int calcs=0;
   for(int c=0;c<nc;c++)
     {
      string sym=ChartSymbol(charts[c]);
      if(sym=="")
         continue;
      datetime h1Bar=iTime(sym,PERIOD_H1,1);
      int s=LvSymIndex(sym);
      bool need=(s<0 || (h1Bar>0 && g_lvS[s].h1Bar!=h1Bar));
      if(need && calcs<LV_MAX_CALC)
        {
         calcs++;
         int r=LvCompute(sym,barsToLoad,h1Bar);
         if(r==1)
           {
            string sum=LvSummaryText(sym);
            if(sum!="")
               LogI(StringFormat("[LEVELS] %s %s",sym,sum));
           }
         else if(r<0)
           {
            // không đủ dữ liệu: ghi nhận để giờ sau mới thử lại, không tính lại mỗi chu kỳ
            LogD(StringFormat("[LEVELS] %s: không đủ dữ liệu D1/H4 để tìm vùng",sym));
            LvRemoveSymbol(sym);
            LvMarkDone(sym,h1Bar,0.0);
           }
         s=LvSymIndex(sym);
        }
      if(s>=0)
         LvDrawChart(charts[c],sym);
     }
  }

void LvDeinit()
  {
   long cid=ChartFirst();
   int guard=0;
   while(cid>=0 && guard<100)
     {
      ObjectsDeleteAll(cid,LV_PREFIX);
      ChartRedraw(cid);
      cid=ChartNext(cid);
      guard++;
     }
   ObjectsDeleteAll(ChartID(),LV_PREFIX);
   ArrayFree(g_lvZ);
   ArrayFree(g_lvS);
   ArrayFree(g_lvChart);
   ArrayFree(g_lvSig);
  }

#endif
