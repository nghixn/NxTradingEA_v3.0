//+------------------------------------------------------------------+
//| Telegram.mqh - gửi thông báo                                     |
//| Giai đoạn 1: tách tin theo giới hạn ký tự + DryRun (in ra log).  |
//| Giai đoạn 4: WebRequest tới api.telegram.org, hàng đợi, retry.   |
//| Include SAU khai báo input.                                      |
//+------------------------------------------------------------------+
#ifndef SIGNALEA_TELEGRAM_MQH
#define SIGNALEA_TELEGRAM_MQH

#include "Common.mqh"

// Tách tin dài thành nhiều phần <= maxLen, ưu tiên cắt theo dòng
int TgSplitMessage(const string text,const int maxLen,string &parts[])
  {
   ArrayResize(parts,0);
   int limit=MathMax(200,maxLen);
   string lines[];
   int n=StringSplit(text,'\n',lines);
   string cur="";
   for(int i=0;i<n;i++)
     {
      string ln=lines[i];
      // dòng đơn lẻ quá dài -> cắt cứng
      while(StringLen(ln)>limit)
        {
         if(cur!="")
           {
            StrArrayPush(parts,cur);
            cur="";
           }
         StrArrayPush(parts,StringSubstr(ln,0,limit));
         ln=StringSubstr(ln,limit);
        }
      int add=(cur=="") ? StringLen(ln) : StringLen(cur)+1+StringLen(ln);
      if(add>limit)
        {
         StrArrayPush(parts,cur);
         cur=ln;
        }
      else
         cur=(cur=="") ? ln : cur+"\n"+ln;
     }
   if(cur!="")
      StrArrayPush(parts,cur);
   return ArraySize(parts);
  }

// In nội dung tin ra tab Experts (mỗi dòng 1 log)
void TgPrintDry(const string text,const int part,const int total)
  {
   Print(StringFormat("[DRYRUN] ----- Tin Telegram (phần %d/%d, %d ký tự) -----",part,total,StringLen(text)));
   string lines[];
   int n=StringSplit(text,'\n',lines);
   for(int i=0;i<n;i++)
      Print("[DRYRUN] ",lines[i]);
  }

bool g_tgStageWarned=false;

// Điểm gửi duy nhất cho mọi loại tin
void NotifySend(const string text)
  {
   string parts[];
   int k=TgSplitMessage(text,InpTgMaxChars,parts);
   bool dry=(InpDryRun || !InpTgEnabled);
   if(!dry && !g_tgStageWarned)
     {
      LogW("Gửi Telegram thật sẽ được bật ở Giai đoạn 4 - hiện tại chỉ in ra log.");
      g_tgStageWarned=true;
     }
   for(int i=0;i<k;i++)
      TgPrintDry(parts[i],i+1,k);
  }

#endif
