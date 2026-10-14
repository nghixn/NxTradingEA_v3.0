//+------------------------------------------------------------------+
//|                                                    SignalEA.mq5  |
//| EA CHỈ BÁO TÍN HIỆU qua Telegram - KHÔNG đặt/sửa/đóng lệnh.      |
//| Không dùng DLL. Không có hàm giao dịch nào trong mã nguồn.       |
//+------------------------------------------------------------------+
#property copyright   "NxTrading"
#property version     "0.20"
#property description "Quét nhiều symbol, phân tích đa khung, gửi tín hiệu Telegram. Không giao dịch."

#include "Include\Common.mqh"

//+------------------------------------------------------------------+
//| INPUT                                                            |
//+------------------------------------------------------------------+
input group "=== 1. Chung ==="
input bool               InpDryRun                 = true;               // DryRun: chỉ in tin ra log, không gọi Telegram
input ENUM_LOG_LEVEL     InpLogLevel               = LOGLVL_INFO;        // Mức log
input int                InpTimerSeconds           = 30;                 // Chu kỳ OnTimer (giây)
input double             InpDisplayGmtOffset       = 7.0;                // Múi giờ hiển thị (GMT+x)
input bool               InpShowPanel              = true;               // Hiện bảng trạng thái trên chart

input group "=== 2. Telegram (gửi thật ở Giai đoạn 4) ==="
input bool               InpTgEnabled              = false;              // Bật gửi Telegram
input string             InpTgToken                = "";                 // Bot token (KHÔNG chia sẻ cho ai)
input string             InpTgChatId               = "";                 // Chat id nhận tin
input int                InpTgMaxChars             = 3800;               // Độ dài tối đa 1 tin (Telegram: 4096)

input group "=== 3. Danh sách & vũ trụ symbol ==="
input string             InpPrioritySymbols        = "BTCUSD,XAUUSD";    // Danh sách ưu tiên (phân cách bằng dấu phẩy)
input string             InpSecondarySymbols       = "ETHUSD,XAGUSD";    // Danh sách phụ
input string             InpSymbolSuffix           = "";                 // Hậu tố symbol (Exness Pro: để trống)
input string             InpForeignSuffixes        = "m,c";              // Hậu tố của loại TK khác cần loại (khi hậu tố trống)
input ENUM_UNIVERSE_MODE InpUniverseMode           = ALL_BROKER_SYMBOLS; // Chế độ vũ trụ quét
input string             InpExcludeSymbols         = "";                 // Loại trừ thủ công (phân cách bằng dấu phẩy)
input bool               InpEnableForex            = true;               // Nhóm Forex
input bool               InpEnableMetals           = true;               // Nhóm Kim loại
input bool               InpEnableCrypto           = true;               // Nhóm Crypto
input bool               InpEnableIndices          = true;               // Nhóm Chỉ số
input bool               InpEnableEnergies         = true;               // Nhóm Năng lượng
input bool               InpEnableStocks           = false;              // Nhóm Cổ phiếu
input bool               InpEnableOther            = false;              // Nhóm không phân loại được

input group "=== 4. Bộ lọc điều kiện ==="
input double             InpMaxSpreadAtrPct        = 15.0;               // Spread tối đa (% ATR H1)
input int                InpMinBarsD1              = 250;                // Số nến D1 tối thiểu
input int                InpMinBarsH1              = 300;                // Số nến H1 tối thiểu
input int                InpMinBarsH4              = 100;                // Số nến H4 tối thiểu
input int                InpMaxQuoteAgeMin         = 60;                 // Báo giá cũ hơn (phút) = coi như nghỉ
input int                InpMaxDeferPerHour        = 3;                  // Số lần hoãn tối đa/giờ (chờ dữ liệu)
input double             InpMaxMinLotRiskPct       = 4.0;                // Ngưỡng cứng: rủi ro ở lot tối thiểu (% số dư)
input double             InpFeasSlAtrMult          = 1.0;                // SL giả định khi lọc vốn (x ATR H4)

input group "=== 5. Hiệu năng (VPS) ==="
input int                InpSymbolsPerCycle        = 5;                  // Số symbol phân tích tối đa mỗi chu kỳ
input int                InpCycleBudgetMs          = 2000;               // Ngân sách thời gian mỗi chu kỳ (ms)
input int                InpMaxMarketWatch         = 60;                 // Giới hạn số symbol trong Market Watch
input bool               InpReleaseSymbolsAfterScan= true;               // Gỡ symbol khám phá khỏi Market Watch sau khi quét
input int                InpUniverseRefreshHours   = 6;                  // Dựng lại danh sách symbol mỗi N giờ
input int                InpBarsToLoad             = 320;                // Số nến tải mỗi khung

input group "=== 6. Chỉ báo ==="
input int                InpSmaFast                = 10;                 // SMA nhanh
input int                InpSmaBase                = 20;                 // SMA cơ sở (bias, độ dốc)
input int                InpSmaMid                 = 50;                 // SMA trung
input int                InpSmaSlow                = 200;                // SMA chậm
input int                InpBbPeriod               = 20;                 // Bollinger: chu kỳ
input double             InpBbDev                  = 2.0;                // Bollinger: độ lệch chuẩn
input int                InpRsiPeriod              = 14;                 // RSI
input int                InpAtrPeriod              = 14;                 // ATR
input int                InpSlopeBars              = 3;                  // Số nến đo độ dốc SMA cơ sở
input bool               InpUseHandlesForWatchlist = false;              // Dùng handle iMA/iBands/... cho ưu tiên/phụ

input group "=== 7. Quản lý vốn (chỉ tính, không giao dịch) ==="
input double             InpRiskPerTradePct        = 1.5;                // % rủi ro mỗi setup
input double             InpMaxTotalRiskPct        = 5.0;                // % tổng rủi ro tối đa các setup đang mở

input group "=== 8. Kiểm thử ==="
input bool               InpSelfTest               = false;              // Chạy self-test chỉ báo + bảng tick value
input string             InpSelfTestSymbols        = "BTCUSD,XAUUSD,EURUSD,USDJPY,US30"; // Symbol self-test (>= 3 nhóm)
input bool               InpLogSnapshots           = true;               // In snapshot chỉ báo của ưu tiên/phụ mỗi giờ

input group "=== 9. Bias & ngưỡng theo tầng ==="
input int                InpWeightMN1              = 1;                  // Trọng số MN1
input int                InpWeightW1               = 2;                  // Trọng số W1
input int                InpWeightD1               = 3;                  // Trọng số D1
input int                InpWeightH4               = 2;                  // Trọng số H4
input int                InpWeightH1               = 1;                  // Trọng số H1
input int                InpBiasMinConditions      = 3;                  // Số điều kiện tối thiểu (trên 4) để khung là tăng/giảm
input int                InpMinScorePriority       = 5;                  // Ưu tiên: |điểm bias| tối thiểu
input double             InpMinRRPriority          = 1.3;                // Ưu tiên: RR TP1 tối thiểu
input int                InpMinScoreOther          = 7;                  // Phụ/Khám phá: |điểm bias| tối thiểu
input double             InpMinRROther             = 1.8;                // Phụ/Khám phá: RR TP1 tối thiểu

input group "=== 10. Setup ==="
input bool               InpEnablePullback         = true;               // Setup chờ hồi (limit)
input bool               InpEnableBreakout         = true;               // Setup phá vỡ (H4)
input double             InpEntryZoneAtrH1         = 0.3;                // Độ rộng vùng Entry (x ATR H1)
input double             InpConfluenceTolAtrH1     = 0.5;                // Dung sai gom yếu tố hội tụ (x ATR H1)
input int                InpMinConfluence          = 2;                  // Số yếu tố hội tụ tối thiểu
input double             InpMaxEntryDistAtrH4      = 2.0;                // Vùng Entry cách giá tối đa (x ATR H4)
input int                InpSwingStrengthH1        = 3;                  // Swing H1: số nến mỗi bên
input int                InpSwingStrengthH4        = 2;                  // Swing H4: số nến mỗi bên
input int                InpSwingStrengthD1        = 2;                  // Swing D1: số nến mỗi bên
input int                InpSwingLookback          = 150;                // Số nến tìm swing
input double             InpSlBufferAtrH4          = 0.25;               // SL: thêm ngoài swing (x ATR H4)
input double             InpSlFallbackAtrH4        = 1.0;                // SL khi không có swing (x ATR H4 ngoài vùng)
input double             InpTpMinGapAtrH4          = 0.3;                // TP phải cách Entry tối thiểu (x ATR H4)
input int                InpSetupExpiryHours       = 24;                 // Hết hạn nếu giá chưa vào vùng (giờ)
input int                InpTriggeredMaxHours      = 72;                 // Ngừng theo dõi sau khi vào vùng (giờ)
input int                InpCooldownMinutes        = 240;                // Cooldown sau khi setup đóng (phút)

input group "=== 11. Xếp hạng, tương quan, chống spam ==="
input int                InpTopK                   = 3;                  // Top K setup phụ/khám phá mỗi vòng quét
input int                InpMaxNewPerDay           = 10;                 // Tin setup mới tối đa/ngày (ưu tiên không tính)
input string             InpCorrelationGroups      = "KIM_LOAI:XAU,XAG,XPT,XPD;CRYPTO:BTC,ETH,LTC,XRP,BCH,SOL,ADA,DOGE;CHI_SO_MY:US30,US500,USTEC,US100;DAU:UKOIL,USOIL,XBR,XTI"; // Nhóm tương quan TÊN:MÃ,...;...
input int                InpMaxCurrencySameSide    = 2;                  // Forex: tối đa số setup cùng phía mỗi đồng tiền

input group "=== 12. Tin tức (best-effort) ==="
input bool               InpNewsEnabled            = true;               // Ghi chú tin mức cao
input int                InpNewsLookaheadMin       = 120;                // Khoảng nhìn trước (phút)
input string             InpNewsCurrencies         = "USD";              // Tiền tệ cần theo dõi
input bool               InpNewsIncludeSymbolCcy   = false;              // Thêm tiền tệ của chính symbol

#include "Include\Risk.mqh"
#include "Include\Indicators.mqh"
#include "Include\Universe.mqh"
#include "Include\Telegram.mqh"
#include "Include\Analysis.mqh"
#include "Include\News.mqh"
#include "Include\Signals.mqh"
#include "Include\SelfTest.mqh"

//+------------------------------------------------------------------+
//| Biến toàn cục                                                    |
//+------------------------------------------------------------------+
IndConfig g_ind;
int       g_barsToLoad=320;
ulong     g_cycleNo=0;
ulong     g_lastCycleMs=0;
ulong     g_maxCycleMs=0;
int       g_lastCycleHeavy=0;
datetime  g_curHourKey=0;
datetime  g_hourStartedAt=0;
bool      g_hourDoneLogged=false;
int       g_analyzedThisHour=0;
datetime  g_lastMwWarn=0;
datetime  g_lastRebuildTry=0;

//+------------------------------------------------------------------+
//| Kiểm tra input                                                   |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   bool ok=true;
   if(InpTimerSeconds<5 || InpTimerSeconds>3600)
     { LogE("InpTimerSeconds phải trong [5..3600]."); ok=false; }
   if(InpSmaFast<1 || InpSmaBase<1 || InpSmaMid<1 || InpSmaSlow<1 || InpBbPeriod<2 || InpRsiPeriod<2 || InpAtrPeriod<1)
     { LogE("Chu kỳ chỉ báo không hợp lệ."); ok=false; }
   if(InpBbDev<=0.0)
     { LogE("InpBbDev phải > 0."); ok=false; }
   if(InpSlopeBars<1)
     { LogE("InpSlopeBars phải >= 1."); ok=false; }
   if(InpSymbolsPerCycle<1 || InpSymbolsPerCycle>50)
     { LogE("InpSymbolsPerCycle phải trong [1..50]."); ok=false; }
   if(InpCycleBudgetMs<200)
     { LogE("InpCycleBudgetMs phải >= 200."); ok=false; }
   if(InpMaxMarketWatch<5)
     { LogE("InpMaxMarketWatch phải >= 5."); ok=false; }
   if(InpTgMaxChars<200 || InpTgMaxChars>4096)
     { LogE("InpTgMaxChars phải trong [200..4096]."); ok=false; }
   if(InpRiskPerTradePct<=0.0 || InpMaxMinLotRiskPct<=0.0 || InpFeasSlAtrMult<=0.0)
     { LogE("Tham số rủi ro phải > 0."); ok=false; }
   if(InpMaxDeferPerHour<1)
     { LogE("InpMaxDeferPerHour phải >= 1."); ok=false; }
   if(InpMinBarsD1<30 || InpMinBarsH1<30 || InpMinBarsH4<30)
     { LogE("Số nến tối thiểu D1/H1/H4 phải >= 30."); ok=false; }
   if(InpWeightMN1<0 || InpWeightW1<0 || InpWeightD1<0 || InpWeightH4<0 || InpWeightH1<0 ||
      InpWeightMN1+InpWeightW1+InpWeightD1+InpWeightH4+InpWeightH1<=0)
     { LogE("Trọng số bias phải >= 0 và tổng > 0."); ok=false; }
   if(InpBiasMinConditions<1 || InpBiasMinConditions>4)
     { LogE("InpBiasMinConditions phải trong [1..4]."); ok=false; }
   if(InpMinRRPriority<=0.0 || InpMinRROther<=0.0 || InpEntryZoneAtrH1<=0.0 || InpConfluenceTolAtrH1<0.0 ||
      InpMaxEntryDistAtrH4<=0.0 || InpSlBufferAtrH4<0.0 || InpSlFallbackAtrH4<=0.0 || InpTpMinGapAtrH4<0.0)
     { LogE("Tham số setup (RR/ATR) không hợp lệ."); ok=false; }
   if(InpMinConfluence<1 || InpSwingStrengthH1<1 || InpSwingStrengthH4<1 || InpSwingStrengthD1<1 || InpSwingLookback<20)
     { LogE("Tham số swing/hội tụ không hợp lệ."); ok=false; }
   if(InpSetupExpiryHours<1 || InpTriggeredMaxHours<1 || InpCooldownMinutes<0 || InpTopK<1 || InpMaxNewPerDay<0 ||
      InpMaxCurrencySameSide<1 || InpMaxTotalRiskPct<=0.0 || InpNewsLookaheadMin<1)
     { LogE("Tham số thời hạn/xếp hạng/rủi ro không hợp lệ."); ok=false; }
   if(InpTgEnabled && !InpDryRun && (InpTgToken=="" || InpTgChatId==""))
      LogW("Telegram đang bật nhưng thiếu token/chat id - tin sẽ chỉ in ra log.");
   return ok;
  }

//+------------------------------------------------------------------+
//| Tin khởi động                                                    |
//+------------------------------------------------------------------+
string ListByTier(const ENUM_SYMBOL_TIER tier)
  {
   string s="";
   int n=ArraySize(g_uni);
   for(int i=0;i<n;i++)
      if(g_uni[i].tier==tier)
         s+=(s=="" ? "" : ", ")+g_uni[i].name;
   return (s=="") ? "(không có)" : s;
  }

string BuildStartupMessage()
  {
   int cnt[AG_COUNT];
   for(int g=0;g<AG_COUNT;g++)
      cnt[g]=0;
   int disc=0;
   int n=ArraySize(g_uni);
   for(int i=0;i<n;i++)
     {
      if(g_uni[i].tier!=TIER_DISCOVERY)
         continue;
      cnt[(int)g_uni[i].assetGroup]++;
      disc++;
     }
   string groups="";
   for(int g=0;g<AG_COUNT;g++)
      if(cnt[g]>0)
         groups+=(groups=="" ? "" : ", ")+GroupName((ENUM_ASSET_GROUP)g)+" "+IntegerToString(cnt[g]);

   string m="["+EA_NAME+"] EA ĐÃ CHẠY - v"+EA_VERSION+" ("+EA_STAGE+")\n";
   m+="Tài khoản: "+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+" | Số dư: "+FmtMoney(RiskBalance())+
      " | Server: "+AccountInfoString(ACCOUNT_SERVER)+"\n";
   m+="Chế độ: "+EnumToString(InpUniverseMode)+" | DryRun: "+(InpDryRun ? "BẬT" : "TẮT")+"\n";
   m+="Ưu tiên: "+ListByTier(TIER_PRIORITY)+"\n";
   m+="Phụ: "+ListByTier(TIER_SECONDARY)+"\n";
   m+="Khám phá: "+IntegerToString(disc)+" symbol"+(groups=="" ? "" : " ("+groups+")")+"\n";
   m+=StringFormat("Ngưỡng: Ưu tiên điểm >= %d, RR >= %.1f | Phụ/Khám phá điểm >= %d, RR >= %.1f | Top %d, tối đa %d tin/ngày\n",
                   InpMinScorePriority,InpMinRRPriority,InpMinScoreOther,InpMinRROther,InpTopK,InpMaxNewPerDay);
   m+=StringFormat("Rủi ro: %.1f%%/setup, tổng tối đa %.1f%%\n",InpRiskPerTradePct,InpMaxTotalRiskPct);
   m+="Thời gian: "+FmtDisplayTime(TimeTradeServer())+"\n";
   m+="EA chỉ báo tín hiệu, không đặt lệnh. Chỉ là tham khảo, không phải lời khuyên đầu tư.";
   return m;
  }

//+------------------------------------------------------------------+
//| Snapshot chỉ báo (log kiểm thử Giai đoạn 1)                      |
//+------------------------------------------------------------------+
void LogSnapshot(const int idx,const SymbolSpec &sp,const TfSnapshot &snap[],const double spread,
                 const double minRisk,const double lotSuggest,const string biasText,const string analysisNote)
  {
   string sym=g_uni[idx].name;
   int dg=sp.digits;
   double bal=RiskBalance();
   string tag="[SNAPSHOT] ";
   LogI(tag+StringFormat("[%s] DỮ LIỆU H1 MỚI (nến %s) - Nhóm: %s | %s",sym,
                         TimeToString(snap[TFI_H1].barTime,TIME_DATE|TIME_MINUTES),
                         TierName(g_uni[idx].tier),GroupName(g_uni[idx].assetGroup)));
   LogI(tag+StringFormat("Giá hiện tại: %s | Thời gian: %s",FmtPrice(sym,SymbolInfoDouble(sym,SYMBOL_BID)),
                         FmtDisplayTime(TimeTradeServer())));
   LogI(tag+StringFormat("Spread: %s = %.1f%% ATR(H1) | Lot min %s rủi ro ≈ %s (%s) với SL %.2f x ATR(H4) | Lot cho %.2f%%: %s",
                         FmtPrice(sym,spread),g_uni[idx].spreadAtrPct,FmtLots(sp,sp.volMin),FmtMoney(minRisk),
                         (bal>0.0) ? DoubleToString(minRisk/bal*100.0,2)+"%" : "n/a",InpFeasSlAtrMult,
                         InpRiskPerTradePct,(lotSuggest>0.0) ? FmtLots(sp,lotSuggest) : "0 (lot min vượt mức)"));
   LogI(tag+"Bias: "+biasText);
   LogI(tag+"Phân tích: "+analysisNote);
   LogI(tag+StringFormat("TF | nến | Close | SMA%d | SMA%d | SMA%d | SMA%d | BB trên | BB dưới | RSI | ATR",
                         g_ind.smaFast,g_ind.smaBase,g_ind.smaMid,g_ind.smaSlow));
   for(int t=0;t<TFI_COUNT;t++)
     {
      if(snap[t].bars<=0)
        {
         LogI(tag+TfName(snap[t].tf)+" | không có dữ liệu");
         continue;
        }
      LogI(tag+StringFormat("%s | %d | %s | %s | %s | %s | %s | %s | %s | %s | %s",
                            TfName(snap[t].tf),snap[t].bars,FmtVal(snap[t].close,dg),
                            FmtVal(snap[t].smaFast,dg),FmtVal(snap[t].smaBase,dg),FmtVal(snap[t].smaMid,dg),
                            FmtVal(snap[t].smaSlow,dg),FmtVal(snap[t].bbUpper,dg),FmtVal(snap[t].bbLower,dg),
                            FmtVal(snap[t].rsi,1),FmtVal(snap[t].atr,dg)));
     }
  }

//+------------------------------------------------------------------+
//| Kết thúc / hoãn xử lý 1 symbol                                   |
//+------------------------------------------------------------------+
void FinishSymbol(const int idx,const datetime hk,const int code,const string text)
  {
   UniSetStatus(idx,code,text);
   g_uni[idx].lastHourKey=hk;
   g_uni[idx].deferCount=0;
   if(!SigHasOpen(g_uni[idx].name) && !SigHasCandidate(g_uni[idx].name))
      UniReleaseIfOwned(idx);
  }

void DeferSymbol(const int idx,const datetime hk,const int code,const string text)
  {
   g_uni[idx].deferCount++;
   if(g_uni[idx].deferCount>=InpMaxDeferPerHour)
     {
      int finalCode=code;
      if(code==SST_HISTORY_LOADING)
         finalCode=SST_HISTORY_MISSING;
      else if(code==SST_WAIT_QUOTE)
         finalCode=SST_STALE_QUOTE;
      FinishSymbol(idx,hk,finalCode,text+" - bỏ qua giờ này");
      return;
     }
   UniSetStatus(idx,code,text);
  }

//+------------------------------------------------------------------+
//| Xử lý 1 symbol. Trả về true nếu đã làm việc nặng (CopyRates).    |
//+------------------------------------------------------------------+
bool ProcessSymbol(const int idx,const datetime hk)
  {
   string sym=g_uni[idx].name;
   datetime now=TimeTradeServer();

   //--- 1. phiên giao dịch
   if(!UniIsInTradeSession(sym,now))
     {
      FinishSymbol(idx,hk,SST_SESSION_CLOSED,"ngoài phiên giao dịch (cuối tuần/ngày nghỉ)");
      return false;
     }
   //--- 2. Market Watch
   if(!UniEnsureSelected(idx))
      return false;
   //--- 3. báo giá
   int q=UniCheckQuote(idx,now);
   if(q==1)
     {
      DeferSymbol(idx,hk,SST_WAIT_QUOTE,"chờ báo giá");
      return false;
     }
   if(q==2)
     {
      FinishSymbol(idx,hk,SST_STALE_QUOTE,StringFormat("không có báo giá mới > %d phút (nghỉ lễ/thanh khoản thấp)",InpMaxQuoteAgeMin));
      return false;
     }
   //--- 4. thông số hợp đồng
   SymbolSpec sp;
   if(!RiskGetSpec(sym,sp))
     {
      FinishSymbol(idx,hk,SST_BAD_SPEC,"thông số hợp đồng bất thường: "+sp.err);
      return false;
     }
   //--- 5. H1 (có nến mới đóng?)
   MqlRates h1[];
   int nH1=IndLoadRates(sym,PERIOD_H1,g_barsToLoad,h1);
   if(nH1<0)
     {
      DeferSymbol(idx,hk,SST_HISTORY_LOADING,(nH1==-2) ? "đang đồng bộ lịch sử H1" : "lỗi CopyRates H1");
      return true;
     }
   if(nH1-1<InpMinBarsH1)
     {
      DeferSymbol(idx,hk,SST_HISTORY_LOADING,StringFormat("H1 chỉ có %d/%d nến",nH1-1,InpMinBarsH1));
      return true;
     }
   if(h1[0].time<hk)
     {
      DeferSymbol(idx,hk,SST_WAIT_QUOTE,"chưa có tick của giờ mới");
      return true;
     }
   if(h1[1].time==g_uni[idx].lastClosedH1)
     {
      FinishSymbol(idx,hk,g_uni[idx].status,g_uni[idx].statusText);
      return true;
     }
   //--- 6. D1, H4 (bắt buộc)
   MqlRates d1[],h4[];
   int nD1=IndLoadRates(sym,PERIOD_D1,g_barsToLoad,d1);
   if(nD1<0 || nD1-1<InpMinBarsD1)
     {
      DeferSymbol(idx,hk,SST_HISTORY_LOADING,
                  (nD1<0) ? "đang đồng bộ lịch sử D1" : StringFormat("D1 chỉ có %d/%d nến",nD1-1,InpMinBarsD1));
      return true;
     }
   int nH4=IndLoadRates(sym,PERIOD_H4,g_barsToLoad,h4);
   if(nH4<0 || nH4-1<InpMinBarsH4)
     {
      DeferSymbol(idx,hk,SST_HISTORY_LOADING,
                  (nH4<0) ? "đang đồng bộ lịch sử H4" : StringFormat("H4 chỉ có %d/%d nến",nH4-1,InpMinBarsH4));
      return true;
     }
   //--- 7. W1, MN1 (tùy chọn: thiếu thì để trống, không lỗi)
   MqlRates w1[],mn1[];
   int nW1=IndLoadRates(sym,PERIOD_W1,g_barsToLoad,w1);
   int nMN=IndLoadRates(sym,PERIOD_MN1,g_barsToLoad,mn1);

   //--- 8. chỉ báo
   TfSnapshot snap[TFI_COUNT];
   IndComputeSnapshot(mn1,MathMax(nMN,0),PERIOD_MN1,g_ind,snap[TFI_MN1]);
   IndComputeSnapshot(w1,MathMax(nW1,0),PERIOD_W1,g_ind,snap[TFI_W1]);
   IndComputeSnapshot(d1,nD1,PERIOD_D1,g_ind,snap[TFI_D1]);
   IndComputeSnapshot(h4,nH4,PERIOD_H4,g_ind,snap[TFI_H4]);
   IndComputeSnapshot(h1,nH1,PERIOD_H1,g_ind,snap[TFI_H1]);
   if(InpUseHandlesForWatchlist && g_uni[idx].tier!=TIER_DISCOVERY)
      for(int t=0;t<TFI_COUNT;t++)
         if(snap[t].bars>0)
            IndApplyHandles(sym,g_ind,snap[t]);

   double atrH1=snap[TFI_H1].atr;
   double atrH4=snap[TFI_H4].atr;
   if(atrH1==EMPTY_VALUE || atrH1<=0.0 || atrH4==EMPTY_VALUE || atrH4<=0.0)
     {
      FinishSymbol(idx,hk,SST_HISTORY_MISSING,"không tính được ATR H1/H4");
      return true;
     }
   g_uni[idx].rsiH1=snap[TFI_H1].rsi;
   g_uni[idx].closeH1=snap[TFI_H1].close;

   //--- 9. spread so với ATR(H1)
   double spread=SymbolInfoDouble(sym,SYMBOL_ASK)-SymbolInfoDouble(sym,SYMBOL_BID);
   double spreadPct=spread/atrH1*100.0;
   g_uni[idx].spreadAtrPct=spreadPct;
   if(spreadPct>InpMaxSpreadAtrPct)
     {
      FinishSymbol(idx,hk,SST_SPREAD_WIDE,StringFormat("spread %s = %.1f%% ATR(H1) > %.1f%%",
                   FmtPrice(sym,spread),spreadPct,InpMaxSpreadAtrPct));
      return true;
     }

   //--- 10. khả thi với vốn (lot tối thiểu, SL giả định)
   double bal=RiskBalance();
   double dist=InpFeasSlAtrMult*atrH4;
   double minRisk=RiskMoney(sp,dist,sp.volMin);
   double minRiskPct=(bal>0.0) ? minRisk/bal*100.0 : EMPTY_VALUE;
   g_uni[idx].minLotRiskPct=minRiskPct;
   if(bal>0.0 && minRiskPct>InpMaxMinLotRiskPct)
     {
      FinishSymbol(idx,hk,SST_CAPITAL,StringFormat("lot tối thiểu %s rủi ro ≈ %s (%.1f%%) > %.1f%% số dư (SL giả định %.2f x ATR H4)",
                   FmtLots(sp,sp.volMin),FmtMoney(minRisk),minRiskPct,InpMaxMinLotRiskPct,InpFeasSlAtrMult));
      return true;
     }
   double lotSuggest=RiskLotForMoney(sp,dist,bal*InpRiskPerTradePct/100.0);

   //--- 11. bias + setup
   string cwhy="";
   bool allow=SigCanCreate(sym,now,cwhy);
   bool newH4=(h4[1].time!=g_uni[idx].lastH4Seen);
   AnaResult res;
   AnaAnalyze(sym,g_uni[idx].tier,h4,nH4,h1,nH1,d1,nD1,snap,newH4,allow,res);
   g_uni[idx].lastH4Seen=h4[1].time;
   g_uni[idx].biasScore=res.score;
   string note=allow ? res.note : cwhy;
   if(res.hasSetup)
     {
      Setup c;
      string why="";
      if(SigBuild(g_uni[idx],res,sp,spreadPct,h4[1].time,c,why))
        {
         note=StringFormat("có setup %s %s, RR %.2f",SideName(c.side),SetupTypeName(c.type),c.rr1);
         SigOnCandidate(c);
        }
      else
        {
         note="setup bị loại: "+why;
         LogI(StringFormat("[%s] %s",sym,note));
        }
     }
   else
      LogD(StringFormat("[%s] không có setup: %s | bias %d/%d",sym,note,res.score,res.maxScore));

   //--- 12. hoàn tất
   g_uni[idx].lastClosedH1=h1[1].time;
   g_uni[idx].lastAnalyzed=now;
   g_analyzedThisHour++;
   FinishSymbol(idx,hk,SST_OK,StringFormat("spread %.1f%% ATR(H1), lot min rủi ro %s, bias %d/%d",spreadPct,
                (minRiskPct==EMPTY_VALUE) ? "n/a" : DoubleToString(minRiskPct,2)+"%",res.score,res.maxScore));
   if(InpLogSnapshots && g_uni[idx].tier!=TIER_DISCOVERY)
      LogSnapshot(idx,sp,snap,spread,minRisk,lotSuggest,AnaBiasText(res),note);
   return true;
  }

//+------------------------------------------------------------------+
//| Vòng quét: ưu tiên/phụ trước, rồi xoay vòng nhóm khám phá        |
//+------------------------------------------------------------------+
bool OverBudget(const ulong t0)
  {
   return (GetTickCount64()-t0>=(ulong)InpCycleBudgetMs);
  }

void RunScanCycle(const datetime hk,const ulong t0)
  {
   g_lastCycleHeavy=0;
   int total=ArraySize(g_uni);
   if(total==0)
      return;
   for(int i=0;i<total;i++)
     {
      if(g_uni[i].tier==TIER_DISCOVERY || !UniIsDue(i,hk))
         continue;
      if(g_lastCycleHeavy>=InpSymbolsPerCycle || OverBudget(t0))
         return;
      if(ProcessSymbol(i,hk))
         g_lastCycleHeavy++;
     }
   int visited=0;
   while(visited<total && g_lastCycleHeavy<InpSymbolsPerCycle && !OverBudget(t0))
     {
      if(g_rrPtr>=total)
         g_rrPtr=0;
      int i=g_rrPtr;
      g_rrPtr=(g_rrPtr+1)%total;
      visited++;
      if(g_uni[i].tier!=TIER_DISCOVERY || !UniIsDue(i,hk))
         continue;
      if(ProcessSymbol(i,hk))
         g_lastCycleHeavy++;
     }
  }

//+------------------------------------------------------------------+
//| Thống kê theo giờ                                                |
//+------------------------------------------------------------------+
string StatusSummary()
  {
   int cnt[SST_COUNT];
   for(int k=0;k<SST_COUNT;k++)
      cnt[k]=0;
   int n=ArraySize(g_uni);
   for(int i=0;i<n;i++)
      if(g_uni[i].status>=0 && g_uni[i].status<SST_COUNT)
         cnt[g_uni[i].status]++;
   string s="";
   for(int k=0;k<SST_COUNT;k++)
      if(cnt[k]>0)
         s+=(s=="" ? "" : " | ")+StatusName(k)+" "+IntegerToString(cnt[k]);
   return s;
  }

int DoneThisHour(const datetime hk)
  {
   int done=0;
   int n=ArraySize(g_uni);
   for(int i=0;i<n;i++)
      if(g_uni[i].lastHourKey==hk)
         done++;
   return done;
  }

void CheckHourDone(const datetime hk,const datetime now)
  {
   if(g_hourDoneLogged)
      return;
   int n=ArraySize(g_uni);
   if(n==0)
      return;
   int done=0,blocked=0;
   for(int i=0;i<n;i++)
     {
      if(g_uni[i].lastHourKey==hk)
         done++;
      else if(g_uni[i].status==SST_MW_FULL)
         blocked++;
     }
   if(done+blocked<n)
      return;
   g_hourDoneLogged=true;
   SigFlushRound(hk);
   LogI(StringFormat("Hoàn tất vòng quét giờ %s sau %d phút: phân tích %d/%d symbol | %s",
                     TimeToString(hk,TIME_DATE|TIME_MINUTES),(int)(((long)now-(long)g_hourStartedAt)/60),
                     g_analyzedThisHour,n,StatusSummary()));
   if(blocked>0)
      LogW(StringFormat("%d symbol khám phá bị bỏ qua vì Market Watch đầy (%d/%d).",blocked,UniMarketWatchCount(),InpMaxMarketWatch));
  }

void CheckMarketWatchLimit(const datetime now)
  {
   int mw=UniMarketWatchCount();
   if(mw<=InpMaxMarketWatch || (long)now-(long)g_lastMwWarn<3600)
      return;
   g_lastMwWarn=now;
   LogW(StringFormat("Market Watch có %d symbol > giới hạn %d: tốn RAM/CPU trên VPS. Hãy ẩn bớt symbol không dùng (chuột phải > Hide).",
                     mw,InpMaxMarketWatch));
  }

//+------------------------------------------------------------------+
//| Bảng trạng thái trên chart                                       |
//+------------------------------------------------------------------+
void UpdatePanel(const string note)
  {
   if(!InpShowPanel)
      return;
   int n=ArraySize(g_uni);
   string s=StringFormat("%s v%s (%s) | DryRun %s | %s\n",EA_NAME,EA_VERSION,EA_STAGE,
                         InpDryRun ? "BẬT" : "TẮT",FmtDisplayTime(TimeTradeServer()));
   if(note!="")
      s+="!!! "+note+"\n";
   s+=StringFormat("Universe: %d nhận / %d loại | Market Watch %d/%d | handle %d\n",
                   n,g_uniRejectedCount,UniMarketWatchCount(),InpMaxMarketWatch,IndHandleCount());
   s+=StringFormat("Chu kỳ #%I64u: %d symbol, %I64u ms (max %I64u ms)\n",g_cycleNo,g_lastCycleHeavy,g_lastCycleMs,g_maxCycleMs);
   s+=StringFormat("Giờ này: %d/%d xong | %s\n",DoneThisHour(g_curHourKey),n,StatusSummary());
   s+="--- Ưu tiên / Phụ ---\n";
   for(int i=0;i<n;i++)
     {
      if(g_uni[i].tier==TIER_DISCOVERY)
         continue;
      s+=StringFormat("%s [%s] %s | bias %+d | RSI H1 %s | spread %s%% ATR | lot min %s%%\n",
                      g_uni[i].name,TierName(g_uni[i].tier),StatusName(g_uni[i].status),g_uni[i].biasScore,
                      FmtVal(g_uni[i].rsiH1,1),FmtVal(g_uni[i].spreadAtrPct,1),FmtVal(g_uni[i].minLotRiskPct,2));
     }
   s+=SigPanelText();
   Comment(s);
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_logLevel=(int)InpLogLevel;
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   g_ind.smaFast=InpSmaFast;
   g_ind.smaBase=InpSmaBase;
   g_ind.smaMid=InpSmaMid;
   g_ind.smaSlow=InpSmaSlow;
   g_ind.bbPeriod=InpBbPeriod;
   g_ind.bbDev=InpBbDev;
   g_ind.rsiPeriod=InpRsiPeriod;
   g_ind.atrPeriod=InpAtrPeriod;
   g_ind.slopeBars=InpSlopeBars;

   //--- số nến cần tải, tôn trọng TERMINAL_MAXBARS
   int need=MathMax(MathMax(InpMinBarsD1,InpMinBarsH1),InpMinBarsH4)+2;
   need=MathMax(need,InpSmaSlow+InpSlopeBars+3);
   g_barsToLoad=MathMax(InpBarsToLoad,need);
   int maxBars=TerminalInfoInteger(TERMINAL_MAXBARS);
   if(maxBars>0 && g_barsToLoad>maxBars)
     {
      LogW(StringFormat("Cần %d nến nhưng TERMINAL_MAXBARS=%d - giảm về %d (Tools > Options > Charts > Max bars).",
                        g_barsToLoad,maxBars,maxBars));
      g_barsToLoad=maxBars;
     }

   TimeInitOffsets(InpDisplayGmtOffset);
   SigInit();
   SigRollDay();
   LogI(StringFormat("=== %s v%s (%s) khởi động | DryRun=%s | server GMT%+.1f | hiển thị %s | tải %d nến/khung ===",
                     EA_NAME,EA_VERSION,EA_STAGE,InpDryRun ? "BẬT" : "TẮT",g_serverGmtOffsetSec/3600.0,
                     g_displayTzLabel,g_barsToLoad));
   if((bool)MQLInfoInteger(MQL_TESTER))
      LogW("Đang chạy trong Strategy Tester: WebRequest/Telegram không hoạt động, chỉ dùng để kiểm thử logic.");

   UniBuild();
   g_lastRebuildTry=TimeTradeServer();
   g_curHourKey=HourKey(g_lastRebuildTry);
   g_hourStartedAt=g_lastRebuildTry;
   if(ArraySize(g_uni)==0)
      LogW("Chưa có symbol nào đủ điều kiện (có thể terminal chưa kết nối) - sẽ thử lại mỗi 5 phút.");

   NotifySend(BuildStartupMessage());

   if(InpSelfTest)
      SelfTestStart(g_ind);

   if(!EventSetTimer(InpTimerSeconds))
     {
      LogE(StringFormat("Không tạo được timer (lỗi %d).",GetLastError()));
      return INIT_FAILED;
     }
   UpdatePanel("");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnTimer: toàn bộ xử lý nằm ở đây (không tính theo tick)          |
//+------------------------------------------------------------------+
void OnTimer()
  {
   ulong t0=GetTickCount64();
   g_cycleNo++;

   if(g_stState==1)
      SelfTestStep(g_ind,g_barsToLoad);

   if(!(bool)TerminalInfoInteger(TERMINAL_CONNECTED))
     {
      UpdatePanel("MẤT KẾT NỐI tới server - tạm dừng quét");
      return;
     }

   datetime now=TimeTradeServer();
   long sinceBuild=(long)now-(long)g_uniBuiltAt;
   long sinceTry=(long)now-(long)g_lastRebuildTry;
   if((ArraySize(g_uni)==0 && sinceTry>=300) ||
      (InpUniverseRefreshHours>0 && sinceBuild>=(long)InpUniverseRefreshHours*3600 && sinceTry>=300))
     {
      g_lastRebuildTry=now;
      UniBuild();
     }

   NewsRefresh(now);
   SigRollDay();
   SigMonitor(now);

   datetime hk=HourKey(now);
   if(hk!=g_curHourKey)
     {
      // vòng quét giờ trước chưa xong vẫn phải xếp hạng ứng viên đã có
      if(ArraySize(g_cands)>0)
         SigFlushRound(g_curHourKey);
      g_curHourKey=hk;
      g_hourStartedAt=now;
      g_hourDoneLogged=false;
      g_analyzedThisHour=0;
      int n=ArraySize(g_uni);
      for(int i=0;i<n;i++)
         g_uni[i].deferCount=0;
     }

   RunScanCycle(hk,t0);
   CheckHourDone(hk,now);
   CheckMarketWatchLimit(now);

   g_lastCycleMs=GetTickCount64()-t0;
   if(g_lastCycleMs>g_maxCycleMs)
      g_maxCycleMs=g_lastCycleMs;
   if(g_lastCycleMs>(ulong)InpCycleBudgetMs*2)
      LogW(StringFormat("Chu kỳ #%I64u mất %I64u ms (> 2 x ngân sách %d ms) - cân nhắc giảm InpSymbolsPerCycle.",
                        g_cycleNo,g_lastCycleMs,InpCycleBudgetMs));
   UpdatePanel("");
  }

//+------------------------------------------------------------------+
//| OnTick: cố ý để trống - không tính toán theo tick                |
//+------------------------------------------------------------------+
void OnTick()
  {
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   SelfTestDeinit();
   IndReleaseAllHandles();
   if(InpReleaseSymbolsAfterScan)
      UniReleaseAllOwned();
   Comment("");
   LogI(StringFormat("%s dừng (mã lý do %d).",EA_NAME,reason));
  }
//+------------------------------------------------------------------+
