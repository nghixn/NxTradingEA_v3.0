//+------------------------------------------------------------------+
//| AiExport.mqh - xuất JSON cho cầu nối Python + Claude API          |
//| Chỉ xuất khi có SETUP MỚI hoặc GIÁ VÀO VÙNG ENTRY (InpAiExport). |
//| File: MQL5/Files/SignalEA/ai_queue/<id>-<event>.json (UTF-8).    |
//| Ghi file tạm rồi đổi tên để script Python không đọc file dở.     |
//| Include SAU Signals.mqh (cần struct Setup).                      |
//+------------------------------------------------------------------+
#ifndef SIGNALEA_AIEXPORT_MQH
#define SIGNALEA_AIEXPORT_MQH

#include "Common.mqh"
#include "Indicators.mqh"
#include "Signals.mqh"

#define AI_SCHEMA     "signalea.setup.v1"
#define AI_QUEUE_DIR  "ai_queue"
#define AI_VALS_PER_TF 12   // barTime, close, sma x4, bb x3, rsi, atr, bias
#define AI_VALS       (AI_VALS_PER_TF*TFI_COUNT)

//--- Snapshot chỉ báo gần nhất của mỗi symbol (để đưa vào JSON)
string g_aiSnapSym[];
double g_aiSnapVal[];       // phẳng: AI_VALS giá trị cho mỗi symbol

void AiSnapStore(const string sym,const TfSnapshot &snap[],const int &biasTf[])
  {
   if(!InpAiExport)
      return;
   int idx=-1;
   int n=ArraySize(g_aiSnapSym);
   for(int i=0;i<n;i++)
      if(g_aiSnapSym[i]==sym)
        {
         idx=i;
         break;
        }
   if(idx<0)
     {
      idx=n;
      ArrayResize(g_aiSnapSym,n+1,32);
      ArrayResize(g_aiSnapVal,(n+1)*AI_VALS,32*AI_VALS);
      g_aiSnapSym[idx]=sym;
     }
   int b=idx*AI_VALS;
   for(int t=0;t<TFI_COUNT;t++)
     {
      int o=b+t*AI_VALS_PER_TF;
      g_aiSnapVal[o+0]=(snap[t].bars>0) ? (double)(long)snap[t].barTime : EMPTY_VALUE;
      g_aiSnapVal[o+1]=snap[t].close;
      g_aiSnapVal[o+2]=snap[t].smaFast;
      g_aiSnapVal[o+3]=snap[t].smaBase;
      g_aiSnapVal[o+4]=snap[t].smaMid;
      g_aiSnapVal[o+5]=snap[t].smaSlow;
      g_aiSnapVal[o+6]=snap[t].bbUpper;
      g_aiSnapVal[o+7]=snap[t].bbMiddle;
      g_aiSnapVal[o+8]=snap[t].bbLower;
      g_aiSnapVal[o+9]=snap[t].rsi;
      g_aiSnapVal[o+10]=snap[t].atr;
      g_aiSnapVal[o+11]=(double)biasTf[t];
     }
  }

//+------------------------------------------------------------------+
//| JSON helpers                                                     |
//+------------------------------------------------------------------+
string AiJsonEsc(const string s)
  {
   string out="";
   int n=StringLen(s);
   for(int i=0;i<n;i++)
     {
      ushort c=StringGetCharacter(s,i);
      if(c=='"')
         out+="\\\"";
      else if(c=='\\')
         out+="\\\\";
      else if(c=='\n')
         out+="\\n";
      else if(c=='\r')
         out+="\\r";
      else if(c=='\t')
         out+="\\t";
      else if(c<0x20)
         out+=StringFormat("\\u%04X",(int)c);
      else
         out+=ShortToString(c);
     }
   return out;
  }

string AiStr(const string s)
  {
   return "\""+AiJsonEsc(s)+"\"";
  }

string AiNum(const double v,const int digits)
  {
   if(v==EMPTY_VALUE || !MathIsValidNumber(v))
      return "null";
   return DoubleToString(v,digits);
  }

string AiBool(const bool b)
  {
   return b ? "true" : "false";
  }

// "2026-10-14T09:00:00"
string AiIsoTime(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t,dt);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02d",dt.year,dt.mon,dt.day,dt.hour,dt.min,dt.sec);
  }

string AiSafeFileName(const string s)
  {
   string out="";
   int n=StringLen(s);
   for(int i=0;i<n;i++)
     {
      ushort c=StringGetCharacter(s,i);
      bool ok=((c>='A' && c<='Z') || (c>='a' && c<='z') || (c>='0' && c<='9') || c=='-' || c=='_');
      out+=ok ? ShortToString(c) : "_";
     }
   return out;
  }

string AiTierCode(const int tier)
  {
   if(tier==TIER_PRIORITY)
      return "priority";
   if(tier==TIER_SECONDARY)
      return "secondary";
   return "discovery";
  }

string AiGroupCode(const int g)
  {
   switch(g)
     {
      case AG_FOREX:    return "forex";
      case AG_METALS:   return "metals";
      case AG_CRYPTO:   return "crypto";
      case AG_INDICES:  return "indices";
      case AG_ENERGIES: return "energies";
      case AG_STOCKS:   return "stocks";
      default:          return "other";
     }
  }

string AiIndicatorsJson(const string sym,const int digits)
  {
   int idx=-1;
   int n=ArraySize(g_aiSnapSym);
   for(int i=0;i<n;i++)
      if(g_aiSnapSym[i]==sym)
        {
         idx=i;
         break;
        }
   if(idx<0)
      return "null";
   string j="{";
   for(int t=0;t<TFI_COUNT;t++)
     {
      int o=idx*AI_VALS+t*AI_VALS_PER_TF;
      double bt=g_aiSnapVal[o+0];
      j+=(t>0 ? "," : "")+AiStr(TfName(g_tfList[t]))+":";
      if(bt==EMPTY_VALUE)
        {
         j+="null";
         continue;
        }
      j+="{\"bar_time\":"+AiStr(AiIsoTime((datetime)(long)bt));
      j+=",\"close\":"+AiNum(g_aiSnapVal[o+1],digits);
      j+=",\"sma"+IntegerToString(InpSmaFast)+"\":"+AiNum(g_aiSnapVal[o+2],digits);
      j+=",\"sma"+IntegerToString(InpSmaBase)+"\":"+AiNum(g_aiSnapVal[o+3],digits);
      j+=",\"sma"+IntegerToString(InpSmaMid)+"\":"+AiNum(g_aiSnapVal[o+4],digits);
      j+=",\"sma"+IntegerToString(InpSmaSlow)+"\":"+AiNum(g_aiSnapVal[o+5],digits);
      j+=",\"bb_up\":"+AiNum(g_aiSnapVal[o+6],digits);
      j+=",\"bb_mid\":"+AiNum(g_aiSnapVal[o+7],digits);
      j+=",\"bb_low\":"+AiNum(g_aiSnapVal[o+8],digits);
      j+=",\"rsi\":"+AiNum(g_aiSnapVal[o+9],2);
      j+=",\"atr\":"+AiNum(g_aiSnapVal[o+10],digits);
      j+=",\"bias\":"+IntegerToString((int)g_aiSnapVal[o+11]);
      j+="}";
     }
   j+="}";
   return j;
  }

//+------------------------------------------------------------------+
//| Dựng JSON cho 1 sự kiện                                          |
//+------------------------------------------------------------------+
string AiBuildJson(const Setup &s,const string ev)
  {
   string sym=s.sym;
   int dg=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   datetime now=TimeTradeServer();
   double bid=SymbolInfoDouble(sym,SYMBOL_BID);
   double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
   double bal=RiskBalance();
   double total=SigTotalRiskMoney();
   SymbolSpec sp;
   int lotDigits=RiskGetSpec(sym,sp) ? RiskStepDigits(sp.volStep) : 2;

   string j="{";
   j+="\"schema\":"+AiStr(AI_SCHEMA);
   j+=",\"event\":"+AiStr(ev);
   j+=",\"id\":"+AiStr(s.id);
   j+=",\"symbol\":"+AiStr(sym);
   j+=",\"tier\":"+AiStr(AiTierCode(s.tier));
   j+=",\"tier_label\":"+AiStr(TierName((ENUM_SYMBOL_TIER)s.tier));
   j+=",\"asset_group\":"+AiStr(AiGroupCode(s.assetGroup));
   j+=",\"digits\":"+IntegerToString(dg);
   j+=",\"time_server\":"+AiStr(AiIsoTime(now));
   j+=",\"time_display\":"+AiStr(FmtDisplayTime(now));
   j+=",\"price\":{\"bid\":"+AiNum(bid,dg)+",\"ask\":"+AiNum(ask,dg)+",\"spread_atr_pct\":"+AiNum(s.spreadPct,2)+"}";
   j+=",\"setup\":{";
   j+="\"type\":"+AiStr((s.type==STYPE_BREAKOUT) ? "breakout" : "pullback");
   j+=",\"side\":"+AiStr((s.side>0) ? "buy" : "sell");
   j+=",\"state\":"+AiStr(SigStateName(s.state));
   j+=",\"entry_low\":"+AiNum(s.entryLow,dg);
   j+=",\"entry_high\":"+AiNum(s.entryHigh,dg);
   j+=",\"entry_ref\":"+AiNum(s.entryRef,dg);
   j+=",\"sl\":"+AiNum(s.sl,dg);
   j+=",\"tp1\":"+AiNum(s.tp1,dg);
   j+=",\"tp2\":"+AiNum(s.tp2,dg);
   j+=",\"rr1\":"+AiNum(s.rr1,2);
   j+=",\"rr2\":"+AiNum(s.rr2,2);
   j+=",\"invalidation\":"+AiStr(SigInvalidText(s));
   j+=",\"expiry_hours\":"+IntegerToString(InpSetupExpiryHours);
   j+=",\"reasons\":"+AiStr(s.reasons);
   j+=",\"confluence_count\":"+IntegerToString(s.confluence);
   j+=",\"created_server\":"+AiStr(AiIsoTime(s.createdAt));
   j+="}";
   j+=",\"bias\":{\"score\":"+IntegerToString(s.score*((s.side>0) ? 1 : -1))+
      ",\"max\":"+IntegerToString(s.maxScore)+",\"text\":"+AiStr(s.biasText)+"}";
   j+=",\"indicators\":"+AiIndicatorsJson(sym,dg);
   j+=",\"risk\":{";
   j+="\"account_currency\":"+AiStr(AccountInfoString(ACCOUNT_CURRENCY));
   j+=",\"balance\":"+AiNum(bal,2);
   j+=",\"lot\":"+AiNum(s.lots,lotDigits);
   j+=",\"risk_money\":"+AiNum(s.riskMoney,2);
   j+=",\"risk_pct\":"+AiNum(s.riskPct,2);
   j+=",\"risk_warning\":"+AiBool(s.riskWarn);
   j+=",\"min_lot_risk_pct\":"+AiNum(s.minLotRiskPct,2);
   j+=",\"total_open_risk_money\":"+AiNum(total,2);
   j+=",\"total_open_risk_pct\":"+AiNum((bal>0.0) ? total/bal*100.0 : EMPTY_VALUE,2);
   j+=",\"max_total_risk_pct\":"+AiNum(InpMaxTotalRiskPct,2);
   j+="}";
   j+=",\"news\":"+AiStr(NewsNoteFor(sym,now));
   j+="}";
   return j;
  }

// Ghi JSON ra hàng đợi. Lỗi chỉ ghi log, không ảnh hưởng EA.
void AiExportEvent(const Setup &s,const string ev)
  {
   if(!InpAiExport)
      return;
   string json=AiBuildJson(s,ev);
   string base=EA_FILES_DIR+"\\"+AI_QUEUE_DIR+"\\"+AiSafeFileName(s.id+"-"+ev);
   string tmp=base+".tmp";
   string fin=base+".json";
   uchar bytes[];
   int n=StringToCharArray(json,bytes,0,WHOLE_ARRAY,CP_UTF8);
   if(n>0 && bytes[n-1]==0)
      n--;
   ResetLastError();
   int h=FileOpen(tmp,FILE_WRITE|FILE_BIN);
   if(h==INVALID_HANDLE)
     {
      LogE(StringFormat("[AI] Không ghi được %s (lỗi %d).",tmp,GetLastError()));
      return;
     }
   FileWriteArray(h,bytes,0,n);
   FileClose(h);
   if(!FileMove(tmp,0,fin,FILE_REWRITE))
     {
      LogE(StringFormat("[AI] Không đổi tên %s -> %s (lỗi %d).",tmp,fin,GetLastError()));
      return;
     }
   LogI("[AI] Đã xuất "+ev+" -> MQL5\\Files\\"+fin);
  }

#endif
