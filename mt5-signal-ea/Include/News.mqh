//+------------------------------------------------------------------+
//| News.mqh - cảnh báo tin tức mức cao (best-effort, lịch MT5)       |
//| Không có dữ liệu lịch -> bỏ qua im lặng, không báo lỗi.           |
//| Thời gian lịch MT5 là giờ server (TimeTradeServer).               |
//| Include SAU khai báo input.                                      |
//+------------------------------------------------------------------+
#ifndef SIGNALEA_NEWS_MQH
#define SIGNALEA_NEWS_MQH

#include "Common.mqh"

datetime g_newsTime[];
string   g_newsCcy[];
string   g_newsName[];
datetime g_newsRefreshedAt=0;
bool     g_newsAvailable=true;

void NewsRefresh(const datetime now)
  {
   if(!InpNewsEnabled || !g_newsAvailable)
      return;
   if((long)now-(long)g_newsRefreshedAt<600)
      return;
   g_newsRefreshedAt=now;
   ArrayResize(g_newsTime,0);
   ArrayResize(g_newsCcy,0);
   ArrayResize(g_newsName,0);
   if((bool)MQLInfoInteger(MQL_TESTER))
     {
      g_newsAvailable=false;
      return;
     }
   MqlCalendarValue vals[];
   datetime to=(datetime)((long)now+(long)(InpNewsLookaheadMin+15)*60);
   ResetLastError();
   if(!CalendarValueHistory(vals,now,to,NULL,NULL))
     {
      LogD(StringFormat("Lịch kinh tế không khả dụng (lỗi %d) - bỏ qua cảnh báo tin.",GetLastError()));
      return;
     }
   int n=ArraySize(vals);
   int cnt=0;
   for(int i=0;i<n;i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id,ev))
         continue;
      if(ev.importance!=CALENDAR_IMPORTANCE_HIGH)
         continue;
      MqlCalendarCountry c;
      if(!CalendarCountryById(ev.country_id,c))
         continue;
      ArrayResize(g_newsTime,cnt+1);
      ArrayResize(g_newsCcy,cnt+1);
      ArrayResize(g_newsName,cnt+1);
      g_newsTime[cnt]=vals[i].time;
      g_newsCcy[cnt]=c.currency;
      g_newsName[cnt]=ev.name;
      cnt++;
     }
   LogD(StringFormat("Lịch kinh tế: %d tin mức cao trong %d phút tới.",cnt,InpNewsLookaheadMin));
  }

// Ghi chú tin mức cao trong InpNewsLookaheadMin phút tới cho symbol, "" nếu không có
string NewsNoteFor(const string sym,const datetime now)
  {
   if(!InpNewsEnabled)
      return "";
   string ccys[];
   SplitCsv(InpNewsCurrencies,ccys);
   if(InpNewsIncludeSymbolCcy)
     {
      string b=SymbolInfoString(sym,SYMBOL_CURRENCY_BASE);
      string q=SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT);
      if(b!="" && !StrInArray(b,ccys))
         StrArrayPush(ccys,b);
      if(q!="" && !StrInArray(q,ccys))
         StrArrayPush(ccys,q);
     }
   string note="";
   int shown=0;
   int n=ArraySize(g_newsTime);
   for(int i=0;i<n && shown<3;i++)
     {
      long dt=(long)g_newsTime[i]-(long)now;
      if(dt<0 || dt>(long)InpNewsLookaheadMin*60)
         continue;
      if(!StrInArray(g_newsCcy[i],ccys))
         continue;
      MqlDateTime t;
      TimeToStruct(ServerToDisplay(g_newsTime[i]),t);
      note+=(shown>0 ? "; " : "")+StringFormat("%s %s lúc %02d:%02d",g_newsCcy[i],g_newsName[i],t.hour,t.min);
      shown++;
     }
   if(note=="")
      return "";
   string win=(InpNewsLookaheadMin%60==0) ? IntegerToString(InpNewsLookaheadMin/60)+" giờ" : IntegerToString(InpNewsLookaheadMin)+" phút";
   return "Lưu ý tin mức cao trong "+win+" tới ("+g_displayTzLabel+"): "+note;
  }

#endif
