//+------------------------------------------------------------------+
//| Risk.mqh - thông số hợp đồng, tính rủi ro và lot gợi ý           |
//| CHỈ TÍNH TOÁN, không có bất kỳ hàm giao dịch nào.                |
//| Dùng SYMBOL_TRADE_TICK_VALUE(_LOSS)/TICK_SIZE: terminal đã quy   |
//| đổi tick value về tiền tệ tài khoản, nên đúng cho mọi loại tài   |
//| sản (Forex, kim loại, crypto, chỉ số, cổ phiếu).                 |
//+------------------------------------------------------------------+
#ifndef SIGNALEA_RISK_MQH
#define SIGNALEA_RISK_MQH

#include "Common.mqh"

struct SymbolSpec
  {
   bool              ok;
   string            err;
   int               digits;
   double            point;
   double            tickSize;
   double            tickValue;       // giá trị 1 tick cho 1 lot (tiền tệ tài khoản)
   double            tickValueLoss;   // giá trị 1 tick khi lỗ (dùng tính rủi ro)
   double            tickValueBroker; // tick value lỗ gốc của broker (trước khi chỉnh thận trọng)
   bool              tvAdjusted;      // true = đã nâng tickValueLoss lên theo kiểm chéo
   double            volMin;
   double            volMax;
   double            volStep;
   double            contractSize;
   string            profitCcy;
  };

#define RCC_OK          0   // khớp trong dung sai
#define RCC_WARN        1   // lệch quá dung sai -> cảnh báo
#define RCC_ABSURD      2   // lệch > 10 lần -> dữ liệu hỏng
#define RCC_UNAVAILABLE 3   // không kiểm chéo được (futures, thiếu tỷ giá...)
// Khai báo trước (định nghĩa bên dưới)
int RiskCrossCheck(const string sym,const SymbolSpec &sp,double &expected,double &diffPct,string &note);

bool RiskGetSpec(const string sym,SymbolSpec &sp)
  {
   sp.ok=false;
   sp.err="";
   sp.digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   sp.point=SymbolInfoDouble(sym,SYMBOL_POINT);
   sp.tickSize=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   sp.tickValue=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   sp.tickValueLoss=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE_LOSS);
   sp.volMin=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   sp.volMax=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   sp.volStep=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   sp.contractSize=SymbolInfoDouble(sym,SYMBOL_TRADE_CONTRACT_SIZE);
   sp.profitCcy=SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT);
   if(sp.tickValueLoss<=0.0)
      sp.tickValueLoss=sp.tickValue;
   if(sp.tickSize<=0.0)
      sp.err=StringFormat("tick size bất thường (%.10g)",sp.tickSize);
   else if(sp.tickValueLoss<=0.0)
      sp.err=StringFormat("tick value bất thường (%.10g)",sp.tickValueLoss);
   else if(sp.volMin<=0.0 || sp.volStep<=0.0)
      sp.err=StringFormat("volume min/step bất thường (%.10g/%.10g)",sp.volMin,sp.volStep);
   else if(sp.volMax<sp.volMin)
      sp.err=StringFormat("volume max < min (%.10g < %.10g)",sp.volMax,sp.volMin);
   sp.ok=(sp.err=="");
   sp.tickValueBroker=sp.tickValueLoss;
   sp.tvAdjusted=false;
   //--- thận trọng: broker báo tick value THẤP hơn tính tay quá dung sai -> dùng số tính tay
   //    (ước thấp rủi ro nguy hiểm hơn ước cao: lot gợi ý không bao giờ vượt ngân sách)
   if(sp.ok)
     {
      double expected=0.0,diff=0.0;
      string note="";
      if(RiskCrossCheck(sym,sp,expected,diff,note)==RCC_WARN && expected>sp.tickValueLoss)
        {
         sp.tickValueLoss=expected;
         sp.tvAdjusted=true;
        }
     }
   return sp.ok;
  }

int RiskStepDigits(const double step)
  {
   int d=0;
   double s=step;
   while(d<8 && MathAbs(s-MathRound(s))>1e-9)
     {
      s*=10.0;
      d++;
     }
   return d;
  }

// Tiền rủi ro (tiền tệ tài khoản) khi giá chạy ngược "dist" với "lots"
double RiskMoney(const SymbolSpec &sp,const double dist,const double lots)
  {
   if(!sp.ok || dist<=0.0 || lots<=0.0)
      return 0.0;
   return lots*(dist/sp.tickSize)*sp.tickValueLoss;
  }

// Lot lớn nhất có rủi ro <= money, làm tròn XUỐNG theo volume step.
// Trả về 0 nếu ngay cả lot tối thiểu đã vượt money.
double RiskLotForMoney(const SymbolSpec &sp,const double dist,const double money)
  {
   if(!sp.ok || dist<=0.0 || money<=0.0)
      return 0.0;
   double perLot=(dist/sp.tickSize)*sp.tickValueLoss;
   if(perLot<=0.0)
      return 0.0;
   double raw=money/perLot;
   double lots=MathFloor(raw/sp.volStep+1e-9)*sp.volStep;
   if(lots>sp.volMax)
      lots=MathFloor(sp.volMax/sp.volStep+1e-9)*sp.volStep;
   if(lots<sp.volMin-1e-12)
      return 0.0;
   return NormalizeDouble(lots,RiskStepDigits(sp.volStep));
  }

double RiskBalance()
  {
   return AccountInfoDouble(ACCOUNT_BALANCE);
  }

string FmtLots(const SymbolSpec &sp,const double lots)
  {
   return DoubleToString(lots,RiskStepDigits(sp.volStep));
  }

//+------------------------------------------------------------------+
//| Kiểm chéo tick value (Giai đoạn 3)                               |
//| Với Forex/CFD/chỉ số/cổ phiếu: lãi lỗ = Δgiá × contract × lot,   |
//| nên tick value kỳ vọng = tick size × contract × tỷ giá quy đổi   |
//| (tiền tệ lợi nhuận -> tiền tệ tài khoản). Futures dùng tick price |
//| nên không kiểm chéo được.                                        |
//| Include SAU khai báo input (dùng InpSymbolSuffix).               |
//+------------------------------------------------------------------+

string g_rccWarned[];       // symbol đã cảnh báo (mỗi phiên chạy 1 lần)

// Tỷ giá quy đổi 1 đơn vị fromCcy sang toCcy (0 nếu không tìm được)
double RiskConvRate(const string fromCcy,const string toCcy,string &via)
  {
   via="";
   if(fromCcy=="" || toCcy=="")
      return 0.0;
   if(fromCcy==toCcy)
     {
      via="cùng tiền tệ";
      return 1.0;
     }
   string cands[2];
   cands[0]=fromCcy+toCcy+InpSymbolSuffix;
   cands[1]=toCcy+fromCcy+InpSymbolSuffix;
   for(int k=0;k<2;k++)
     {
      bool isCustom=false;
      if(!SymbolExist(cands[k],isCustom))
         continue;
      if(!(bool)SymbolInfoInteger(cands[k],SYMBOL_SELECT))
         SymbolSelect(cands[k],true);
      double bid=SymbolInfoDouble(cands[k],SYMBOL_BID);
      double ask=SymbolInfoDouble(cands[k],SYMBOL_ASK);
      if(bid<=0.0 || ask<=0.0)
         continue;
      double mid=(bid+ask)*0.5;
      via=cands[k];
      return (k==0) ? mid : 1.0/mid;
     }
   return 0.0;
  }

int RiskCrossCheck(const string sym,const SymbolSpec &sp,double &expected,double &diffPct,string &note)
  {
   expected=0.0;
   diffPct=0.0;
   note="";
   if(!sp.ok)
     {
      note="spec lỗi";
      return RCC_UNAVAILABLE;
     }
   ENUM_SYMBOL_CALC_MODE cm=(ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(sym,SYMBOL_TRADE_CALC_MODE);
   bool linear=(cm==SYMBOL_CALC_MODE_FOREX || cm==SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE ||
                cm==SYMBOL_CALC_MODE_CFD || cm==SYMBOL_CALC_MODE_CFDINDEX ||
                cm==SYMBOL_CALC_MODE_CFDLEVERAGE || cm==SYMBOL_CALC_MODE_EXCH_STOCKS);
   if(!linear)
     {
      note="không kiểm chéo được với kiểu tính "+EnumToString(cm);
      return RCC_UNAVAILABLE;
     }
   if(sp.contractSize<=0.0)
     {
      note="contract size bất thường";
      return RCC_UNAVAILABLE;
     }
   string acc=AccountInfoString(ACCOUNT_CURRENCY);
   string via="";
   double rate=RiskConvRate(sp.profitCcy,acc,via);
   if(rate<=0.0)
     {
      note=StringFormat("không tìm được tỷ giá %s -> %s",sp.profitCcy,acc);
      return RCC_UNAVAILABLE;
     }
   expected=sp.tickSize*sp.contractSize*rate;
   if(expected<=0.0)
     {
      note="giá trị kỳ vọng bằng 0";
      return RCC_UNAVAILABLE;
     }
   double broker=sp.tickValueBroker;
   diffPct=(broker-expected)/expected*100.0;
   note=StringFormat("kiểm chéo: tick size %.10g x contract %.10g x tỷ giá %s->%s %.6g (%s) = %.6g; broker %.6g; lệch %.2f%%",
                     sp.tickSize,sp.contractSize,sp.profitCcy,acc,rate,via,expected,broker,diffPct);
   double ratio=broker/expected;
   if(ratio>10.0 || ratio<0.1)
      return RCC_ABSURD;
   if(MathAbs(diffPct)>InpTickValueTolPct)
      return RCC_WARN;
   return RCC_OK;
  }

// Dùng trong pipeline: false = loại symbol (dữ liệu hỏng). Cảnh báo lệch chỉ log 1 lần/phiên.
bool RiskSpecSane(const string sym,const SymbolSpec &sp,string &why)
  {
   double expected=0.0,diff=0.0;
   string note="";
   int r=RiskCrossCheck(sym,sp,expected,diff,note);
   if(r==RCC_ABSURD)
     {
      why="tick value bất thường ("+note+")";
      return false;
     }
   if(r==RCC_WARN && !StrInArray(sym,g_rccWarned))
     {
      StrArrayPush(g_rccWarned,sym);
      LogW(StringFormat("[RISK] %s: tick value broker lệch %.2f%% so với tính tay - %s. %s",sym,diff,
                        sp.tvAdjusted ? "dùng số tính tay (lớn hơn, thận trọng)" : "vẫn dùng số của broker (lớn hơn)",note));
     }
   return true;
  }

// Diễn giải cách tính lot để đối chiếu tay
string RiskBreakdown(const string sym,const SymbolSpec &sp,const double dist,const double lots,const double riskPctTarget)
  {
   double bal=RiskBalance();
   double ticks=(sp.tickSize>0.0) ? dist/sp.tickSize : 0.0;
   double perLot=ticks*sp.tickValueLoss;
   double budget=bal*riskPctTarget/100.0;
   double raw=(perLot>0.0) ? budget/perLot : 0.0;
   double risk=RiskMoney(sp,dist,lots);
   return StringFormat("SL cách %s = %.1f tick x %.6g %s/tick/lot = %s/lot | ngân sách %.2f%% x %s = %s -> %.4f lot -> làm tròn xuống step %s (min %s) = %s lot | rủi ro %s (%.2f%%)",
                       DoubleToString(dist,sp.digits),ticks,sp.tickValueLoss,AccountInfoString(ACCOUNT_CURRENCY),
                       FmtMoney(perLot),riskPctTarget,FmtMoney(bal),FmtMoney(budget),raw,
                       FmtLots(sp,sp.volStep),FmtLots(sp,sp.volMin),FmtLots(sp,lots),FmtMoney(risk),
                       (bal>0.0) ? risk/bal*100.0 : 0.0);
  }

#endif
