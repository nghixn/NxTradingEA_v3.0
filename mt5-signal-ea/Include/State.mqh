//+------------------------------------------------------------------+
//| State.mqh - lưu/đọc trạng thái setup ra MQL5/Files/SignalEA/      |
//| File: state_<login>.txt (UTF-16, mỗi dòng 1 bản ghi, phân cách |) |
//| Ghi qua file tạm rồi đổi tên để không hỏng file khi mất điện.     |
//| Khởi động lại EA -> nạp lại setup đang mở + cooldown -> không báo |
//| trùng.                                                           |
//+------------------------------------------------------------------+
#ifndef SIGNALEA_STATE_MQH
#define SIGNALEA_STATE_MQH

#include "Common.mqh"
#include "Signals.mqh"
#include "Universe.mqh"

#define STATE_VERSION   "1"
#define STATE_FIELDS    37

bool   g_stateLoaded=false;   // chỉ ghi file sau khi đã nạp (tránh ghi đè bằng dữ liệu rỗng)
string g_stateFile="";        // cố định theo tài khoản lúc nạp (tránh ghi nhầm khi đổi tài khoản)

string StateFileName()
  {
   return EA_FILES_DIR+"\\state_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+".txt";
  }

string StateClean(const string s)
  {
   string t=s;
   StringReplace(t,"|","/");
   StringReplace(t,"\r"," ");
   StringReplace(t,"\n"," ");
   if(t=="")
      t="~";            // giữ chỗ cho chuỗi rỗng
   return t;
  }

string StateS(const string f)
  {
   return (f=="~") ? "" : f;
  }

string StateD(const double v)
  {
   if(v==EMPTY_VALUE)
      return "E";
   return DoubleToString(v,10);
  }

double StateParseD(const string s)
  {
   if(s=="E")
      return EMPTY_VALUE;
   return StringToDouble(s);
  }

string StateT(const datetime t)
  {
   return IntegerToString((long)t);
  }

string StateSetupLine(const Setup &s)
  {
   string f[];
   ArrayResize(f,STATE_FIELDS);
   f[0]=StateClean(s.id);
   f[1]=StateClean(s.sym);
   f[2]=StateClean(s.corrGroup);
   f[3]=StateClean(s.baseCcy);
   f[4]=StateClean(s.quoteCcy);
   f[5]=StateClean(s.reasons);
   f[6]=StateClean(s.biasText);
   f[7]=StateClean(s.newsNote);
   f[8]=IntegerToString(s.tier);
   f[9]=IntegerToString(s.assetGroup);
   f[10]=IntegerToString(s.side);
   f[11]=IntegerToString(s.type);
   f[12]=IntegerToString(s.score);
   f[13]=IntegerToString(s.maxScore);
   f[14]=IntegerToString(s.confluence);
   f[15]=IntegerToString(s.state);
   f[16]=StateD(s.entryLow);
   f[17]=StateD(s.entryHigh);
   f[18]=StateD(s.entryRef);
   f[19]=StateD(s.sl);
   f[20]=StateD(s.tp1);
   f[21]=StateD(s.tp2);
   f[22]=StateD(s.rr1);
   f[23]=StateD(s.rr2);
   f[24]=StateD(s.lots);
   f[25]=StateD(s.riskMoney);
   f[26]=StateD(s.riskPct);
   f[27]=StateD(s.minLotRiskMoney);
   f[28]=StateD(s.minLotRiskPct);
   f[29]=StateD(s.spreadPct);
   f[30]=StateD(s.quality);
   f[31]=s.riskWarn ? "1" : "0";
   f[32]=StateT(s.createdAt);
   f[33]=StateT(s.expiresAt);
   f[34]=StateT(s.triggeredAt);
   f[35]=StateT(s.closedAt);
   f[36]=StateT(s.lastH4Checked);
   string line="S";
   for(int i=0;i<STATE_FIELDS;i++)
      line+="|"+f[i];
   return line;
  }

bool StateParseSetup(const string &f[],const int n,Setup &s)
  {
   // f[0] = "S", dữ liệu từ f[1]
   if(n<STATE_FIELDS+1)
      return false;
   s.id=StateS(f[1]);
   s.sym=StateS(f[2]);
   s.corrGroup=StateS(f[3]);
   s.baseCcy=StateS(f[4]);
   s.quoteCcy=StateS(f[5]);
   s.reasons=StateS(f[6]);
   s.biasText=StateS(f[7]);
   s.newsNote=StateS(f[8]);
   s.tier=(int)StringToInteger(f[9]);
   s.assetGroup=(int)StringToInteger(f[10]);
   s.side=(int)StringToInteger(f[11]);
   s.type=(int)StringToInteger(f[12]);
   s.score=(int)StringToInteger(f[13]);
   s.maxScore=(int)StringToInteger(f[14]);
   s.confluence=(int)StringToInteger(f[15]);
   s.state=(int)StringToInteger(f[16]);
   s.entryLow=StateParseD(f[17]);
   s.entryHigh=StateParseD(f[18]);
   s.entryRef=StateParseD(f[19]);
   s.sl=StateParseD(f[20]);
   s.tp1=StateParseD(f[21]);
   s.tp2=StateParseD(f[22]);
   s.rr1=StateParseD(f[23]);
   s.rr2=StateParseD(f[24]);
   s.lots=StateParseD(f[25]);
   s.riskMoney=StateParseD(f[26]);
   s.riskPct=StateParseD(f[27]);
   s.minLotRiskMoney=StateParseD(f[28]);
   s.minLotRiskPct=StateParseD(f[29]);
   s.spreadPct=StateParseD(f[30]);
   s.quality=StateParseD(f[31]);
   s.riskWarn=(f[32]=="1");
   s.createdAt=(datetime)StringToInteger(f[33]);
   s.expiresAt=(datetime)StringToInteger(f[34]);
   s.triggeredAt=(datetime)StringToInteger(f[35]);
   s.closedAt=(datetime)StringToInteger(f[36]);
   s.lastH4Checked=(datetime)StringToInteger(f[37]);
   if(s.sym=="" || (s.side!=SIDE_BUY && s.side!=SIDE_SELL) || s.state<SS_ACTIVE || s.state>SS_DONE)
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Ghi                                                              |
//+------------------------------------------------------------------+
bool StateSave()
  {
   if(!g_stateLoaded || g_stateFile=="")
      return false;
   string fname=g_stateFile;
   string tmp=fname+".tmp";
   ResetLastError();
   int h=FileOpen(tmp,FILE_WRITE|FILE_TXT|FILE_UNICODE);
   if(h==INVALID_HANDLE)
     {
      LogE(StringFormat("Không ghi được file trạng thái %s (lỗi %d).",tmp,GetLastError()));
      return false;
     }
   FileWriteString(h,StringFormat("H|%s|%d|%d|%d|%d|%d|%d|%d|%d|%d|%I64d\r\n",STATE_VERSION,g_sigDayKey,g_sigNewToday,
                                  g_dayNewPri,g_dayNewOther,g_dayTriggered,g_dayInvalid,g_dayExpired,g_dayDone,
                                  g_summarySentDay,(long)TimeTradeServer()));
   int n=ArraySize(g_setups);
   for(int i=0;i<n;i++)
      FileWriteString(h,StateSetupLine(g_setups[i])+"\r\n");
   FileClose(h);
   ResetLastError();
   if(!FileMove(tmp,0,fname,FILE_REWRITE))
     {
      LogE(StringFormat("Không đổi tên %s -> %s (lỗi %d).",tmp,fname,GetLastError()));
      return false;
     }
   g_stateDirty=false;
   LogD(StringFormat("Đã lưu trạng thái: %d setup -> MQL5\\Files\\%s",n,fname));
   return true;
  }

//+------------------------------------------------------------------+
//| Đọc khi khởi động                                                |
//+------------------------------------------------------------------+
int StateLoad()
  {
   string fname=StateFileName();
   g_stateFile=fname;
   g_stateLoaded=true;
   if(!FileIsExist(fname))
     {
      LogI("Chưa có file trạng thái ("+fname+") - bắt đầu mới.");
      return 0;
     }
   ResetLastError();
   int h=FileOpen(fname,FILE_READ|FILE_TXT|FILE_UNICODE|FILE_SHARE_READ);
   if(h==INVALID_HANDLE)
     {
      // không ghi đè file đang lỗi đọc: tạm dừng lưu trạng thái trong phiên này
      LogE(StringFormat("Không đọc được file trạng thái %s (lỗi %d) - bắt đầu mới, KHÔNG ghi đè file cũ.",fname,GetLastError()));
      g_stateLoaded=false;
      return 0;
     }
   ArrayResize(g_setups,0);
   int loaded=0,bad=0,open=0;
   while(!FileIsEnding(h))
     {
      string line=StrTrim(FileReadString(h));
      if(line=="")
         continue;
      string f[];
      int k=StringSplit(line,'|',f);
      if(k<=0)
         continue;
      if(f[0]=="H")
        {
         if(k>=11 && f[1]==STATE_VERSION)
           {
            g_sigDayKey=(int)StringToInteger(f[2]);
            g_sigNewToday=(int)StringToInteger(f[3]);
            g_dayNewPri=(int)StringToInteger(f[4]);
            g_dayNewOther=(int)StringToInteger(f[5]);
            g_dayTriggered=(int)StringToInteger(f[6]);
            g_dayInvalid=(int)StringToInteger(f[7]);
            g_dayExpired=(int)StringToInteger(f[8]);
            g_dayDone=(int)StringToInteger(f[9]);
            g_summarySentDay=(int)StringToInteger(f[10]);
           }
         continue;
        }
      if(f[0]!="S")
         continue;
      Setup s;
      if(!StateParseSetup(f,k,s))
        {
         bad++;
         continue;
        }
      int n=ArraySize(g_setups);
      ArrayResize(g_setups,n+1,16);
      SetupCopy(g_setups[n],s);
      loaded++;
      if(SigIsOpenState(s.state))
         open++;
     }
   FileClose(h);
   if(bad>0)
      LogW(StringFormat("File trạng thái có %d dòng lỗi - đã bỏ qua.",bad));
   LogI(StringFormat("Đã nạp trạng thái: %d setup (%d đang mở) từ MQL5\\Files\\%s.",loaded,open,fname));
   g_stateDirty=false;
   return open;
  }

// Symbol có setup đang mở phải có trong Market Watch để theo dõi giá
void StateEnsureSymbolsSelected()
  {
   int n=ArraySize(g_setups);
   for(int i=0;i<n;i++)
     {
      if(!SigIsOpenState(g_setups[i].state))
         continue;
      string sym=g_setups[i].sym;
      bool isCustom=false;
      if(!SymbolExist(sym,isCustom))
        {
         LogW("Setup "+g_setups[i].id+": symbol không còn tồn tại - đóng setup.");
         g_setups[i].state=SS_EXPIRED;
         g_setups[i].closedAt=TimeTradeServer();
         g_stateDirty=true;
         continue;
        }
      if((bool)SymbolInfoInteger(sym,SYMBOL_SELECT))
         continue;
      if(SymbolSelect(sym,true))
        {
         int ui=UniFind(sym);
         if(ui>=0)
           {
            g_uni[ui].selectedByEA=true;
            g_uni[ui].selectedAt=TimeTradeServer();
           }
        }
     }
  }

#endif
