//+------------------------------------------------------------------+
//| Telegram.mqh - gửi tin qua WebRequest (sendMessage)               |
//| - Tách tin theo giới hạn ký tự                                   |
//| - DryRun: chỉ in ra log                                          |
//| - Hàng đợi giữ thứ tự, giãn cách tối thiểu giữa 2 tin             |
//| - Thử lại tối đa InpTgMaxRetries lần, giãn cách tăng dần          |
//| - Tôn trọng HTTP 429 retry_after                                 |
//| Token không bao giờ được in ra log.                              |
//| Include SAU khai báo input.                                      |
//+------------------------------------------------------------------+
#ifndef SIGNALEA_TELEGRAM_MQH
#define SIGNALEA_TELEGRAM_MQH

#include "Common.mqh"

#define TG_HOST       "https://api.telegram.org"
#define TG_QUEUE_MAX  100
#define TG_TIMEOUT_MS 5000

struct TgItem
  {
   string            text;
   int               attempts;
   ulong             nextTryMs;
  };

TgItem   g_tgQ[];
ulong    g_tgLastSendMs=0;
int      g_tgSent=0;
int      g_tgFailed=0;
string   g_tgLastStatus="chưa gửi";
datetime g_tgLastGuideAt=0;
bool     g_tgWarnedConfig=false;

// Tách tin dài thành nhiều phần <= maxLen, ưu tiên cắt theo dòng
int TgSplitMessage(const string text,const int maxLen,string &parts[])
  {
   ArrayResize(parts,0);
   int limit=IntMax(200,maxLen);
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

// Gửi thật chỉ khi: tắt DryRun, bật Telegram, đủ token/chat id, không chạy trong Tester
bool TgIsLive()
  {
   if(InpDryRun || !InpTgEnabled)
      return false;
   if((bool)MQLInfoInteger(MQL_TESTER))
      return false;
   return (StrTrim(InpTgToken)!="" && StrTrim(InpTgChatId)!="");
  }

string TgFirstLine(const string text)
  {
   int p=StringFind(text,"\n");
   string s=(p<0) ? text : StringSubstr(text,0,p);
   if(StringLen(s)>100)
      s=StringSubstr(s,0,100)+"...";
   return s;
  }

//+------------------------------------------------------------------+
//| Điểm gửi duy nhất cho mọi loại tin                               |
//+------------------------------------------------------------------+
void NotifySend(const string text)
  {
   string parts[];
   int k=TgSplitMessage(text,InpTgMaxChars,parts);
   if(!TgIsLive())
     {
      if(!InpDryRun && InpTgEnabled && !g_tgWarnedConfig)
        {
         LogW("Telegram đang bật nhưng thiếu token/chat id (hoặc đang chạy trong Tester) - tin chỉ in ra log.");
         g_tgWarnedConfig=true;
        }
      for(int i=0;i<k;i++)
         TgPrintDry(parts[i],i+1,k);
      return;
     }
   for(int i=0;i<k;i++)
     {
      int n=ArraySize(g_tgQ);
      if(n>=TG_QUEUE_MAX)
        {
         // bỏ tin cũ nhất, in ra log để không mất nội dung
         LogW("Hàng đợi Telegram đầy - bỏ tin cũ nhất: "+TgFirstLine(g_tgQ[0].text));
         TgPrintDry(g_tgQ[0].text,1,1);
         for(int j=1;j<n;j++)
           {
            g_tgQ[j-1].text=g_tgQ[j].text;
            g_tgQ[j-1].attempts=g_tgQ[j].attempts;
            g_tgQ[j-1].nextTryMs=g_tgQ[j].nextTryMs;
           }
         n--;
         ArrayResize(g_tgQ,n);
        }
      ArrayResize(g_tgQ,n+1,16);
      g_tgQ[n].text=parts[i];
      g_tgQ[n].attempts=0;
      g_tgQ[n].nextTryMs=0;
      LogD("[TG] xếp hàng: "+TgFirstLine(parts[i]));
     }
  }

//+------------------------------------------------------------------+
//| HTTP                                                             |
//+------------------------------------------------------------------+
// URL-encode theo UTF-8 (application/x-www-form-urlencoded)
string TgUrlEncode(const string s)
  {
   char bytes[];
   int n=StringToCharArray(s,bytes,0,WHOLE_ARRAY,CP_UTF8);
   if(n>0 && bytes[n-1]==0)
      n--;
   string out="";
   for(int i=0;i<n;i++)
     {
      int b=((int)bytes[i])&0xFF;
      bool keep=((b>='A' && b<='Z') || (b>='a' && b<='z') || (b>='0' && b<='9') ||
                 b=='-' || b=='_' || b=='.' || b=='~');
      if(keep)
         out+=CharToString((uchar)b);
      else
         out+=StringFormat("%%%02X",b);
     }
   return out;
  }

// Lấy giá trị số sau "key": trong JSON đơn giản, -1 nếu không có
long TgJsonInt(const string json,const string key)
  {
   int p=StringFind(json,"\""+key+"\":");
   if(p<0)
      return -1;
   p+=StringLen(key)+3;
   string num="";
   int len=StringLen(json);
   while(p<len)
     {
      ushort c=StringGetCharacter(json,p);
      if(c>='0' && c<='9')
         num+=ShortToString(c);
      else if(num!="")
         break;
      p++;
     }
   return (num=="") ? -1 : StringToInteger(num);
  }

string TgJsonDescription(const string json)
  {
   int p=StringFind(json,"\"description\":\"");
   if(p<0)
      return "";
   p+=15;
   int e=StringFind(json,"\"",p);
   if(e<0)
      return "";
   return StringSubstr(json,p,e-p);
  }

void TgPrintWebRequestGuide(const int err)
  {
   datetime now=TimeLocal();
   if((long)now-(long)g_tgLastGuideAt<600)
      return;
   g_tgLastGuideAt=now;
   LogE(StringFormat("WebRequest bị chặn (lỗi %d). Cách khắc phục:",err));
   LogE("  Tools -> Options -> Expert Advisors -> tick 'Allow WebRequest for listed URL' -> thêm "+TG_HOST);
   LogE("  Sau đó gắn lại EA. Tin trong hàng đợi sẽ được thử lại.");
  }

// Gửi 1 tin. Trả về mã HTTP (200 = OK) hoặc -1 nếu WebRequest lỗi (err = GetLastError)
int TgPost(const string text,string &resp,int &err)
  {
   string url=TG_HOST+"/bot"+StrTrim(InpTgToken)+"/sendMessage";
   string body="chat_id="+TgUrlEncode(StrTrim(InpTgChatId))+"&text="+TgUrlEncode(text)+
               "&disable_web_page_preview=true";
   char data[];
   int n=StringToCharArray(body,data,0,WHOLE_ARRAY,CP_UTF8);
   if(n>0 && data[n-1]==0)
      ArrayResize(data,n-1);
   char result[];
   string resHeaders="";
   string headers="Content-Type: application/x-www-form-urlencoded\r\n";
   ResetLastError();
   int code=WebRequest("POST",url,headers,TG_TIMEOUT_MS,data,result,resHeaders);
   err=(code==-1) ? GetLastError() : 0;
   resp=(ArraySize(result)>0) ? CharArrayToString(result,0,WHOLE_ARRAY,CP_UTF8) : "";
   return code;
  }

void TgDropHead(const string reason)
  {
   int n=ArraySize(g_tgQ);
   if(n==0)
      return;
   if(reason!="")
     {
      g_tgFailed++;
      LogE("Bỏ tin Telegram sau khi gửi lỗi ("+reason+"). Nội dung in dưới đây để không mất:");
      TgPrintDry(g_tgQ[0].text,1,1);
     }
   for(int j=1;j<n;j++)
     {
      g_tgQ[j-1].text=g_tgQ[j].text;
      g_tgQ[j-1].attempts=g_tgQ[j].attempts;
      g_tgQ[j-1].nextTryMs=g_tgQ[j].nextTryMs;
     }
   ArrayResize(g_tgQ,n-1);
  }

// Gọi mỗi giây: gửi tối đa 1 tin (tin đầu hàng đợi) nếu đã đủ giãn cách
void TgProcessQueue()
  {
   if(ArraySize(g_tgQ)==0)
      return;
   if(!TgIsLive())
     {
      // cấu hình bị đổi giữa chừng: in hết ra log
      while(ArraySize(g_tgQ)>0)
        {
         TgPrintDry(g_tgQ[0].text,1,1);
         TgDropHead("");
        }
      return;
     }
   ulong nowMs=GetTickCount64();
   if(g_tgLastSendMs>0 && nowMs-g_tgLastSendMs<(ulong)InpTgMinIntervalMs)
      return;
   if(g_tgQ[0].nextTryMs>nowMs)
      return;

   string resp="";
   int err=0;
   int code=TgPost(g_tgQ[0].text,resp,err);
   g_tgLastSendMs=GetTickCount64();

   if(code==200)
     {
      g_tgSent++;
      g_tgLastStatus="OK "+TimeToString(TimeLocal(),TIME_MINUTES);
      LogI("[TG] đã gửi: "+TgFirstLine(g_tgQ[0].text));
      TgDropHead("");
      return;
     }

   //--- lỗi không nên thử lại: token/chat id sai, bot bị chặn
   if(code==400 || code==401 || code==403 || code==404)
     {
      string desc=TgJsonDescription(resp);
      string hint="";
      if(code==401 || code==404)
         hint="token sai hoặc bot đã bị xóa - kiểm tra InpTgToken";
      else if(code==403)
         hint="bot bị chặn hoặc chưa bấm Start với bot / chưa thêm bot vào group";
      else
         hint="kiểm tra InpTgChatId (group dạng -100...)";
      g_tgLastStatus=StringFormat("LỖI HTTP %d",code);
      LogE(StringFormat("Telegram từ chối (HTTP %d: %s) - %s.",code,desc,hint));
      TgDropHead(StringFormat("HTTP %d",code));
      return;
     }

   //--- quá giới hạn tốc độ: chờ đúng retry_after, không tính là 1 lần thử
   if(code==429)
     {
      long ra=TgJsonInt(resp,"retry_after");
      if(ra<1)
         ra=5;
      g_tgQ[0].nextTryMs=GetTickCount64()+(ulong)ra*1000;
      g_tgLastStatus=StringFormat("429 chờ %I64d s",ra);
      LogW(StringFormat("Telegram giới hạn tốc độ (429) - chờ %I64d giây.",ra));
      return;
     }

   //--- lỗi mạng / WebRequest / 5xx: thử lại với giãn cách tăng dần
   if(code==-1 && (err==4014 || err==4060 || err==5200))
      TgPrintWebRequestGuide(err);
   g_tgQ[0].attempts++;
   g_tgLastStatus=(code==-1) ? StringFormat("LỖI WebRequest %d",err) : StringFormat("LỖI HTTP %d",code);
   if(g_tgQ[0].attempts>InpTgMaxRetries)
     {
      TgDropHead(g_tgLastStatus+StringFormat(", đã thử lại %d lần",InpTgMaxRetries));
      return;
     }
   int delaySec=5;
   for(int i=1;i<g_tgQ[0].attempts;i++)
      delaySec*=3;                       // 5s, 15s, 45s...
   g_tgQ[0].nextTryMs=GetTickCount64()+(ulong)delaySec*1000;
   LogW(StringFormat("Gửi Telegram lỗi (%s) - thử lại lần %d/%d sau %d giây.",g_tgLastStatus,
                     g_tgQ[0].attempts,InpTgMaxRetries,delaySec));
  }

int TgQueueSize()
  {
   return ArraySize(g_tgQ);
  }

// Khi gỡ EA: in các tin chưa gửi ra log để không mất
void TgDeinit()
  {
   int n=ArraySize(g_tgQ);
   if(n==0)
      return;
   LogW(StringFormat("Còn %d tin Telegram chưa gửi khi dừng EA - in ra log:",n));
   for(int i=0;i<n;i++)
      TgPrintDry(g_tgQ[i].text,i+1,n);
   ArrayFree(g_tgQ);
  }

string TgStatusText()
  {
   if(!TgIsLive())
      return InpDryRun ? "DryRun (chỉ in log)" : "TẮT/thiếu cấu hình (chỉ in log)";
   return StringFormat("đã gửi %d, lỗi %d, chờ %d | %s",g_tgSent,g_tgFailed,ArraySize(g_tgQ),g_tgLastStatus);
  }

#endif
