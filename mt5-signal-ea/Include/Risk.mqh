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
   double            volMin;
   double            volMax;
   double            volStep;
   double            contractSize;
   string            profitCcy;
  };

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

#endif
