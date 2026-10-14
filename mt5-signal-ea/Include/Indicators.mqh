//+------------------------------------------------------------------+
//| Indicators.mqh - SMA/BB/RSI/ATR tự tính từ CopyRates             |
//| + cache handle (tùy chọn) cho danh sách ưu tiên/phụ.             |
//| Mảng rates dùng dạng series: [0] = nến đang chạy, [1] = nến đã   |
//| đóng gần nhất. Mọi giá trị được tính tại shift 1 (nến đã đóng).  |
//| Công thức khớp chỉ báo chuẩn của MT5:                            |
//|  - SMA: trung bình cộng close                                    |
//|  - BB : SMA +/- dev * độ lệch chuẩn tổng thể (chia cho period)   |
//|  - RSI: làm trơn Wilder, khởi tạo bằng trung bình period đầu     |
//|  - ATR: trung bình cộng (SMA) của True Range (ATR.mq5 của MT5)   |
//+------------------------------------------------------------------+
#ifndef SIGNALEA_INDICATORS_MQH
#define SIGNALEA_INDICATORS_MQH

#include "Common.mqh"

struct IndConfig
  {
   int               smaFast;    // mặc định 10
   int               smaBase;    // mặc định 20
   int               smaMid;     // mặc định 50
   int               smaSlow;    // mặc định 200
   int               bbPeriod;   // 20
   double            bbDev;      // 2.0
   int               rsiPeriod;  // 14
   int               atrPeriod;  // 14
   int               slopeBars;  // số nến để đo độ dốc SMA base
  };

struct TfSnapshot
  {
   ENUM_TIMEFRAMES   tf;
   bool              ok;           // đủ dữ liệu tối thiểu (SMA base + ATR)
   int               bars;         // số nến đã đóng có sẵn
   datetime          barTime;      // giờ mở nến đã đóng gần nhất
   double            open;
   double            high;
   double            low;
   double            close;
   double            smaFast;
   double            smaBase;
   double            smaMid;
   double            smaSlow;
   double            smaBasePrev;  // SMA base tại shift 1+slopeBars
   double            bbUpper;
   double            bbMiddle;
   double            bbLower;
   double            rsi;
   double            atr;
  };

void IndResetSnapshot(TfSnapshot &s,const ENUM_TIMEFRAMES tf)
  {
   s.tf=tf;
   s.ok=false;
   s.bars=0;
   s.barTime=0;
   s.open=EMPTY_VALUE;
   s.high=EMPTY_VALUE;
   s.low=EMPTY_VALUE;
   s.close=EMPTY_VALUE;
   s.smaFast=EMPTY_VALUE;
   s.smaBase=EMPTY_VALUE;
   s.smaMid=EMPTY_VALUE;
   s.smaSlow=EMPTY_VALUE;
   s.smaBasePrev=EMPTY_VALUE;
   s.bbUpper=EMPTY_VALUE;
   s.bbMiddle=EMPTY_VALUE;
   s.bbLower=EMPTY_VALUE;
   s.rsi=EMPTY_VALUE;
   s.atr=EMPTY_VALUE;
  }

//+------------------------------------------------------------------+
//| Tải nến. Trả về: >0 số nến; -1 lỗi; -2 đang đồng bộ lịch sử      |
//+------------------------------------------------------------------+
int IndLoadRates(const string sym,const ENUM_TIMEFRAMES tf,const int want,MqlRates &r[])
  {
   ArrayFree(r);
   if(!(bool)SeriesInfoInteger(sym,tf,SERIES_SYNCHRONIZED))
     {
      // kích hoạt tải/xây dựng timeseries ở nền, lượt sau đọc lại
      Bars(sym,tf);
      datetime t[];
      CopyTime(sym,tf,0,1,t);
      return -2;
     }
   ResetLastError();
   int n=CopyRates(sym,tf,0,want,r);
   if(n<=0)
     {
      LogD(StringFormat("%s %s: CopyRates lỗi %d",sym,TfName(tf),GetLastError()));
      return -1;
     }
   ArraySetAsSeries(r,true);
   return n;
  }

//+------------------------------------------------------------------+
//| Các hàm tính (series)                                            |
//+------------------------------------------------------------------+
double IndSMA(const MqlRates &r[],const int n,const int period,const int shift)
  {
   if(period<=0 || shift<0 || shift+period>n)
      return EMPTY_VALUE;
   double sum=0.0;
   for(int i=shift;i<shift+period;i++)
      sum+=r[i].close;
   return sum/period;
  }

bool IndBands(const MqlRates &r[],const int n,const int period,const double dev,const int shift,
              double &upper,double &middle,double &lower)
  {
   upper=EMPTY_VALUE;
   middle=EMPTY_VALUE;
   lower=EMPTY_VALUE;
   double ma=IndSMA(r,n,period,shift);
   if(ma==EMPTY_VALUE)
      return false;
   double sq=0.0;
   for(int i=shift;i<shift+period;i++)
     {
      double d=r[i].close-ma;
      sq+=d*d;
     }
   double sd=MathSqrt(sq/period);
   middle=ma;
   upper=ma+dev*sd;
   lower=ma-dev*sd;
   return true;
  }

double IndRSI(const MqlRates &r[],const int n,const int period,const int shift)
  {
   if(period<=0 || shift<0 || n-shift<period+1)
      return EMPTY_VALUE;
   int oldest=n-1;
   int start=oldest-1;              // nến cũ nhất có nến trước nó
   double pos=0.0,neg=0.0;
   for(int k=0;k<period;k++)
     {
      int i=start-k;
      double d=r[i].close-r[i+1].close;
      if(d>0.0)
         pos+=d;
      else
         neg-=d;
     }
   pos/=period;
   neg/=period;
   for(int i=start-period;i>=shift;i--)
     {
      double d=r[i].close-r[i+1].close;
      double up=(d>0.0) ? d : 0.0;
      double dn=(d<0.0) ? -d : 0.0;
      pos=(pos*(period-1)+up)/period;
      neg=(neg*(period-1)+dn)/period;
     }
   if(neg!=0.0)
      return 100.0-100.0/(1.0+pos/neg);
   return (pos!=0.0) ? 100.0 : 50.0;
  }

double IndTrueRange(const MqlRates &r[],const int i)
  {
   double prevClose=r[i+1].close;
   return MathMax(r[i].high,prevClose)-MathMin(r[i].low,prevClose);
  }

double IndATR(const MqlRates &r[],const int n,const int period,const int shift)
  {
   // cần thêm 1 nến trước để có close trước đó
   if(period<=0 || shift<0 || shift+period+1>n)
      return EMPTY_VALUE;
   double sum=0.0;
   for(int i=shift;i<shift+period;i++)
      sum+=IndTrueRange(r,i);
   return sum/period;
  }

//+------------------------------------------------------------------+
//| Tính snapshot 1 khung từ rates                                   |
//+------------------------------------------------------------------+
void IndComputeSnapshot(const MqlRates &r[],const int n,const ENUM_TIMEFRAMES tf,
                        const IndConfig &c,TfSnapshot &s)
  {
   IndResetSnapshot(s,tf);
   if(n<3)
      return;
   s.bars=n-1;
   s.barTime=r[1].time;
   s.open=r[1].open;
   s.high=r[1].high;
   s.low=r[1].low;
   s.close=r[1].close;
   s.smaFast=IndSMA(r,n,c.smaFast,1);
   s.smaBase=IndSMA(r,n,c.smaBase,1);
   s.smaMid=IndSMA(r,n,c.smaMid,1);
   s.smaSlow=IndSMA(r,n,c.smaSlow,1);       // MN1/W1 có thể thiếu -> EMPTY_VALUE
   s.smaBasePrev=IndSMA(r,n,c.smaBase,1+c.slopeBars);
   IndBands(r,n,c.bbPeriod,c.bbDev,1,s.bbUpper,s.bbMiddle,s.bbLower);
   s.rsi=IndRSI(r,n,c.rsiPeriod,1);
   s.atr=IndATR(r,n,c.atrPeriod,1);
   s.ok=(s.smaBase!=EMPTY_VALUE && s.atr!=EMPTY_VALUE);
  }

//+------------------------------------------------------------------+
//| Cache handle chỉ báo chuẩn (chỉ dùng cho ưu tiên/phụ nếu bật)    |
//+------------------------------------------------------------------+
#define IK_SMA   0
#define IK_BANDS 1
#define IK_RSI   2
#define IK_ATR   3

struct HandleEntry
  {
   string            sym;
   ENUM_TIMEFRAMES   tf;
   int               kind;
   int               period;
   int               handle;
  };

HandleEntry g_hCache[];

int IndCreateHandle(const string sym,const ENUM_TIMEFRAMES tf,const int kind,const int period,const double dev)
  {
   ResetLastError();
   int h=INVALID_HANDLE;
   switch(kind)
     {
      case IK_SMA:   h=iMA(sym,tf,period,0,MODE_SMA,PRICE_CLOSE); break;
      case IK_BANDS: h=iBands(sym,tf,period,0,dev,PRICE_CLOSE);  break;
      case IK_RSI:   h=iRSI(sym,tf,period,PRICE_CLOSE);          break;
      case IK_ATR:   h=iATR(sym,tf,period);                      break;
     }
   if(h==INVALID_HANDLE)
      LogW(StringFormat("%s %s: không tạo được handle chỉ báo (kind=%d, period=%d), lỗi %d",
                        sym,TfName(tf),kind,period,GetLastError()));
   return h;
  }

int IndHandleGet(const string sym,const ENUM_TIMEFRAMES tf,const int kind,const int period,const double dev)
  {
   int n=ArraySize(g_hCache);
   for(int i=0;i<n;i++)
      if(g_hCache[i].sym==sym && g_hCache[i].tf==tf && g_hCache[i].kind==kind && g_hCache[i].period==period)
         return g_hCache[i].handle;
   int h=IndCreateHandle(sym,tf,kind,period,dev);
   if(h==INVALID_HANDLE)
      return INVALID_HANDLE;
   ArrayResize(g_hCache,n+1);
   g_hCache[n].sym=sym;
   g_hCache[n].tf=tf;
   g_hCache[n].kind=kind;
   g_hCache[n].period=period;
   g_hCache[n].handle=h;
   return h;
  }

// Giá trị buffer tại shift; EMPTY_VALUE nếu chưa tính xong
double IndHandleValue(const int h,const int buffer,const int shift)
  {
   if(h==INVALID_HANDLE)
      return EMPTY_VALUE;
   if(BarsCalculated(h)<=shift)
      return EMPTY_VALUE;
   double v[];
   if(CopyBuffer(h,buffer,shift,1,v)!=1)
      return EMPTY_VALUE;
   if(v[0]==EMPTY_VALUE || !MathIsValidNumber(v[0]))
      return EMPTY_VALUE;
   return v[0];
  }

// Ghi đè giá trị snapshot bằng handle; giá trị nào chưa sẵn sàng thì giữ bản tự tính
void IndApplyHandles(const string sym,const IndConfig &c,TfSnapshot &s)
  {
   double v;
   v=IndHandleValue(IndHandleGet(sym,s.tf,IK_SMA,c.smaFast,0.0),0,1);
   if(v!=EMPTY_VALUE) s.smaFast=v;
   v=IndHandleValue(IndHandleGet(sym,s.tf,IK_SMA,c.smaBase,0.0),0,1);
   if(v!=EMPTY_VALUE) s.smaBase=v;
   v=IndHandleValue(IndHandleGet(sym,s.tf,IK_SMA,c.smaMid,0.0),0,1);
   if(v!=EMPTY_VALUE) s.smaMid=v;
   v=IndHandleValue(IndHandleGet(sym,s.tf,IK_SMA,c.smaSlow,0.0),0,1);
   if(v!=EMPTY_VALUE) s.smaSlow=v;
   int hb=IndHandleGet(sym,s.tf,IK_BANDS,c.bbPeriod,c.bbDev);
   v=IndHandleValue(hb,0,1);
   if(v!=EMPTY_VALUE) s.bbMiddle=v;
   v=IndHandleValue(hb,1,1);
   if(v!=EMPTY_VALUE) s.bbUpper=v;
   v=IndHandleValue(hb,2,1);
   if(v!=EMPTY_VALUE) s.bbLower=v;
   v=IndHandleValue(IndHandleGet(sym,s.tf,IK_RSI,c.rsiPeriod,0.0),0,1);
   if(v!=EMPTY_VALUE) s.rsi=v;
   v=IndHandleValue(IndHandleGet(sym,s.tf,IK_ATR,c.atrPeriod,0.0),0,1);
   if(v!=EMPTY_VALUE) s.atr=v;
  }

int IndHandleCount()
  {
   return ArraySize(g_hCache);
  }

void IndReleaseAllHandles()
  {
   int n=ArraySize(g_hCache);
   for(int i=0;i<n;i++)
      if(g_hCache[i].handle!=INVALID_HANDLE)
         IndicatorRelease(g_hCache[i].handle);
   ArrayFree(g_hCache);
   if(n>0)
      LogI(StringFormat("Đã giải phóng %d handle chỉ báo.",n));
  }

#endif
