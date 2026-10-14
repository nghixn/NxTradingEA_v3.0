//+------------------------------------------------------------------+
//| SelfTest.mqh - đối chiếu chỉ báo tự tính với iMA/iBands/iRSI/iATR |
//| và in bảng thông số rủi ro (tick value) để đối chiếu Exness.     |
//| Chạy 1 lần khi InpSelfTest=true, theo từng nhịp OnTimer.          |
//| Include SAU khai báo input và sau Indicators/Risk/Universe.       |
//+------------------------------------------------------------------+
#ifndef SIGNALEA_SELFTEST_MQH
#define SIGNALEA_SELFTEST_MQH

#include "Common.mqh"
#include "Indicators.mqh"
#include "Risk.mqh"
#include "Universe.mqh"

struct SelfTestItem
  {
   string            sym;
   ENUM_ASSET_GROUP  assetGroup;
   ENUM_TIMEFRAMES   tf;
   int               hSma[4];
   int               hBands;
   int               hRsi;
   int               hAtr;
  };

SelfTestItem g_st[];
int          g_stState=0;   // 0 tắt, 1 đang chờ, 2 xong
int          g_stWait=0;
string       g_stSymbols[];

void SelfTestReleaseHandles()
  {
   int n=ArraySize(g_st);
   for(int i=0;i<n;i++)
     {
      for(int k=0;k<4;k++)
         if(g_st[i].hSma[k]!=INVALID_HANDLE)
            IndicatorRelease(g_st[i].hSma[k]);
      if(g_st[i].hBands!=INVALID_HANDLE)
         IndicatorRelease(g_st[i].hBands);
      if(g_st[i].hRsi!=INVALID_HANDLE)
         IndicatorRelease(g_st[i].hRsi);
      if(g_st[i].hAtr!=INVALID_HANDLE)
         IndicatorRelease(g_st[i].hAtr);
     }
   ArrayFree(g_st);
  }

void SelfTestStart(const IndConfig &c)
  {
   ENUM_TIMEFRAMES tfs[3]={PERIOD_H1,PERIOD_H4,PERIOD_D1};
   string items[];
   int n=SplitCsv(InpSelfTestSymbols,items);
   ArrayResize(g_stSymbols,0);
   for(int i=0;i<n;i++)
     {
      string sym=UniResolveName(items[i]);
      bool isCustom=false;
      if(!SymbolExist(sym,isCustom))
        {
         LogE("[SELFTEST] Symbol '"+sym+"' không tồn tại - bỏ qua.");
         continue;
        }
      if(!SymbolSelect(sym,true))
        {
         LogE(StringFormat("[SELFTEST] Không thêm được %s vào Market Watch (lỗi %d).",sym,GetLastError()));
         continue;
        }
      StrArrayPush(g_stSymbols,sym);
      ENUM_ASSET_GROUP g=UniClassify(sym);
      for(int t=0;t<3;t++)
        {
         int k=ArraySize(g_st);
         ArrayResize(g_st,k+1);
         g_st[k].sym=sym;
         g_st[k].assetGroup=g;
         g_st[k].tf=tfs[t];
         g_st[k].hSma[0]=IndCreateHandle(sym,tfs[t],IK_SMA,c.smaFast,0.0);
         g_st[k].hSma[1]=IndCreateHandle(sym,tfs[t],IK_SMA,c.smaBase,0.0);
         g_st[k].hSma[2]=IndCreateHandle(sym,tfs[t],IK_SMA,c.smaMid,0.0);
         g_st[k].hSma[3]=IndCreateHandle(sym,tfs[t],IK_SMA,c.smaSlow,0.0);
         g_st[k].hBands=IndCreateHandle(sym,tfs[t],IK_BANDS,c.bbPeriod,c.bbDev);
         g_st[k].hRsi=IndCreateHandle(sym,tfs[t],IK_RSI,c.rsiPeriod,0.0);
         g_st[k].hAtr=IndCreateHandle(sym,tfs[t],IK_ATR,c.atrPeriod,0.0);
        }
     }
   g_stState=(ArraySize(g_st)>0) ? 1 : 2;
   g_stWait=0;
   LogI(StringFormat("[SELFTEST] Bắt đầu: %d symbol x 3 khung (H1/H4/D1). Kết quả sẽ in sau vài chu kỳ timer.",
                     ArraySize(g_stSymbols)));
  }

bool SelfTestHandleReady(const int h)
  {
   return (h==INVALID_HANDLE || BarsCalculated(h)>0);
  }

void SelfTestCmp(const string label,const double self,const double ref,const double tol,const int dg,
                 string &line,int &pass,int &fail)
  {
   if(self==EMPTY_VALUE || ref==EMPTY_VALUE)
     {
      line+=label+" n/a | ";
      return;
     }
   bool ok=(MathAbs(self-ref)<=tol);
   line+=StringFormat("%s %s/%s %s | ",label,DoubleToString(self,dg),DoubleToString(ref,dg),ok ? "OK" : "LỆCH");
   if(ok)
      pass++;
   else
      fail++;
  }

void SelfTestPrintRisk(const IndConfig &c,const int barsToLoad)
  {
   double bal=RiskBalance();
   LogI(StringFormat("[RISK] Số dư %s | tiền tệ TK %s | rủi ro/lệnh %.2f%% | SL giả định = %.2f x ATR(H4)",
                     FmtMoney(bal),AccountInfoString(ACCOUNT_CURRENCY),InpRiskPerTradePct,InpFeasSlAtrMult));
   int n=ArraySize(g_stSymbols);
   for(int i=0;i<n;i++)
     {
      string sym=g_stSymbols[i];
      SymbolSpec sp;
      if(!RiskGetSpec(sym,sp))
        {
         LogE("[RISK] "+sym+": "+sp.err);
         continue;
        }
      MqlRates r[];
      int nr=IndLoadRates(sym,PERIOD_H4,barsToLoad,r);
      double atr=(nr>0) ? IndATR(r,nr,c.atrPeriod,1) : EMPTY_VALUE;
      LogI(StringFormat("[RISK] %s | tick size %s | tick value %.6g (lỗ %.6g) %s/lot | contract %.6g %s | lot min %s step %s max %s",
                        sym,DoubleToString(sp.tickSize,sp.digits),sp.tickValue,sp.tickValueLoss,
                        AccountInfoString(ACCOUNT_CURRENCY),sp.contractSize,sp.profitCcy,
                        FmtLots(sp,sp.volMin),FmtLots(sp,sp.volStep),FmtLots(sp,sp.volMax)));
      if(atr==EMPTY_VALUE)
        {
         LogW("[RISK] "+sym+": chưa có ATR(H4) - bỏ qua phần tính lot.");
         continue;
        }
      double dist=InpFeasSlAtrMult*atr;
      double riskMin=RiskMoney(sp,dist,sp.volMin);
      double riskBudget=bal*InpRiskPerTradePct/100.0;
      double lot=RiskLotForMoney(sp,dist,riskBudget);
      string pct=(bal>0.0) ? DoubleToString(riskMin/bal*100.0,2)+"%" : "n/a";
      LogI(StringFormat("[RISK] %s | ATR(H4) %s | SL %s (= %.0f tick) | lot min rủi ro %s (%s) | lot cho %.2f%% (%s): %s",
                        sym,FmtPrice(sym,atr),FmtPrice(sym,dist),dist/sp.tickSize,FmtMoney(riskMin),pct,
                        InpRiskPerTradePct,FmtMoney(riskBudget),
                        (lot>0.0) ? FmtLots(sp,lot) : "0 (lot tối thiểu vượt ngưỡng)"));
     }
  }

void SelfTestStep(const IndConfig &c,const int barsToLoad)
  {
   if(g_stState!=1)
      return;
   int n=ArraySize(g_st);
   bool ready=true;
   for(int i=0;i<n && ready;i++)
     {
      for(int k=0;k<4;k++)
         if(!SelfTestHandleReady(g_st[i].hSma[k]))
            ready=false;
      if(!SelfTestHandleReady(g_st[i].hBands) || !SelfTestHandleReady(g_st[i].hRsi) || !SelfTestHandleReady(g_st[i].hAtr))
         ready=false;
     }
   if(!ready && g_stWait<10)
     {
      g_stWait++;
      LogI(StringFormat("[SELFTEST] Chờ chỉ báo chuẩn tính xong (%d/10)...",g_stWait));
      return;
     }

   int pass=0,fail=0;
   bool groupsSeen[AG_COUNT];
   for(int g=0;g<AG_COUNT;g++)
      groupsSeen[g]=false;
   string csvName=EA_FILES_DIR+"\\selftest_values.csv";
   int fh=FileOpen(csvName,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(fh!=INVALID_HANDLE)
      FileWrite(fh,"symbol","tf","bar_time","close","sma_fast","sma_base","sma_mid","sma_slow",
                "bb_upper","bb_middle","bb_lower","rsi","atr");

   for(int i=0;i<n;i++)
     {
      string sym=g_st[i].sym;
      MqlRates r[];
      int nr=IndLoadRates(sym,g_st[i].tf,barsToLoad,r);
      if(nr<0)
        {
         LogW(StringFormat("[SELFTEST] %s %s: chưa tải được nến (mã %d) - bỏ qua.",sym,TfName(g_st[i].tf),nr));
         continue;
        }
      TfSnapshot s;
      IndComputeSnapshot(r,nr,g_st[i].tf,c,s);
      int dg=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
      double tol=MathMax(SymbolInfoDouble(sym,SYMBOL_POINT),1e-8);
      int p0=pass,f0=fail;
      string l1=StringFormat("[SELFTEST] %s %s nến %s | ",sym,TfName(g_st[i].tf),TimeToString(s.barTime,TIME_DATE|TIME_MINUTES));
      SelfTestCmp("SMA"+IntegerToString(c.smaFast),s.smaFast,IndHandleValue(g_st[i].hSma[0],0,1),tol,dg,l1,pass,fail);
      SelfTestCmp("SMA"+IntegerToString(c.smaBase),s.smaBase,IndHandleValue(g_st[i].hSma[1],0,1),tol,dg,l1,pass,fail);
      SelfTestCmp("SMA"+IntegerToString(c.smaMid),s.smaMid,IndHandleValue(g_st[i].hSma[2],0,1),tol,dg,l1,pass,fail);
      SelfTestCmp("SMA"+IntegerToString(c.smaSlow),s.smaSlow,IndHandleValue(g_st[i].hSma[3],0,1),tol,dg,l1,pass,fail);
      string l2=StringFormat("[SELFTEST] %s %s | ",sym,TfName(g_st[i].tf));
      SelfTestCmp("BBup",s.bbUpper,IndHandleValue(g_st[i].hBands,1,1),tol,dg,l2,pass,fail);
      SelfTestCmp("BBmid",s.bbMiddle,IndHandleValue(g_st[i].hBands,0,1),tol,dg,l2,pass,fail);
      SelfTestCmp("BBlow",s.bbLower,IndHandleValue(g_st[i].hBands,2,1),tol,dg,l2,pass,fail);
      SelfTestCmp("RSI",s.rsi,IndHandleValue(g_st[i].hRsi,0,1),0.05,2,l2,pass,fail);
      SelfTestCmp("ATR",s.atr,IndHandleValue(g_st[i].hAtr,0,1),tol,dg,l2,pass,fail);
      LogI(l1);
      LogI(l2+((fail>f0) ? "=> CÓ LỆCH" : (pass>p0 ? "=> KHỚP" : "=> chưa so được")));
      if(pass>p0)
         groupsSeen[(int)g_st[i].assetGroup]=true;
      if(fh!=INVALID_HANDLE)
         FileWrite(fh,sym,TfName(g_st[i].tf),TimeToString(s.barTime,TIME_DATE|TIME_MINUTES),
                   DoubleToString(s.close,dg),FmtVal(s.smaFast,dg),FmtVal(s.smaBase,dg),FmtVal(s.smaMid,dg),
                   FmtVal(s.smaSlow,dg),FmtVal(s.bbUpper,dg),FmtVal(s.bbMiddle,dg),FmtVal(s.bbLower,dg),
                   FmtVal(s.rsi,2),FmtVal(s.atr,dg));
     }
   if(fh!=INVALID_HANDLE)
     {
      FileClose(fh);
      LogI("[SELFTEST] Giá trị tự tính đã ghi vào MQL5\\Files\\"+csvName+" (để đối chiếu ExportChartData).");
     }
   int groups=0;
   string gl="";
   for(int g=0;g<AG_COUNT;g++)
      if(groupsSeen[g])
        {
         groups++;
         gl+=(gl=="" ? "" : ", ")+GroupName((ENUM_ASSET_GROUP)g);
        }
   LogI(StringFormat("[SELFTEST] KẾT QUẢ: %d khớp, %d lệch | %d symbol, %d nhóm tài sản (%s) | %s",
                     pass,fail,ArraySize(g_stSymbols),groups,gl,
                     (fail==0 && pass>0) ? "ĐẠT" : "CẦN KIỂM TRA"));
   SelfTestPrintRisk(c,barsToLoad);
   SelfTestReleaseHandles();
   g_stState=2;
  }

void SelfTestDeinit()
  {
   SelfTestReleaseHandles();
   g_stState=0;
  }

#endif
