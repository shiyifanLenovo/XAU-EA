//+------------------------------------------------------------------+
//|                                                    DS-顶底分型代码.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Indicators\Indicator.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\OrderInfo.mqh> // 包含OrderInfo类

CDealInfo m_deal;        // 交易信息对象
CTrade trade;            // 交易操作对象
CPositionInfo positionInfo; // 仓位信息对象
CSymbolInfo m_symbol;    // 交易品种信息对象
COrderInfo  orderInfo;


input group "基本参数"
input int MagicNumber = 888; // EA唯一编号
input double InitialLot = 0.01; // 初始化手数
input double MaxLot = 0.8;     // 最大手数
input int MaxSpread = 161; // 最大可接受的点差
input int MaxSlippage = 3; // 最大可接受的滑点
input double LossPercent     =15.0 ;      // 强制平仓比
input int barCount = 30;  //需要处理的K线数量
input int MaxPostionBuyOrderNum= 3;    // 最大做多单
input ENUM_TIMEFRAMES Current_TimeFrame = PERIOD_M5;    // 当前时间周期
input double Balance=9699;       //账户结余
input int EMA_8 =8;             //趋势均线    
input double MartingaleMultiplier = 2.0; //亏损时需要增加的 n 倍手数 

int OnInit(){
   trade.SetExpertMagicNumber(MagicNumber);
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason){
   ObjectsDeleteAll(0, "Fractal_"); // 清除旧标记
   
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){

    string logText = "-----顶底分型V1.0版本----\n---图表周期---: " + EnumToString(_Period) +
                    "\n---时间---: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
     //Buy单信号函数
    CheckBugEntrySignal();
    //多单止损信号函数,
    BuyCheckExitSignal();
    //Sell单信号函数
    CheckSellEntrySignal();
    SellCheckExitSignal();
    LossExceedingThreshold();
}

// 定义分型结构体
struct Fractal{
    int direction;  // 1=顶分型, -1=底分型
    datetime time;  // 分型时间
    double price;   // 分型价格（顶分型取高点，底分型取低点）
    int originalIndex;  // 原始K线索引（从右往左，0=最新K线）
};


//做多信号
void CheckBugEntrySignal(){
       static datetime lastCheckTime = 0;
       datetime now = TimeCurrent();
       if(now - lastCheckTime < 8){
            return;
       }
       lastCheckTime = now;
       Fractal fractals[];
       BuildFindFractals(fractals);
       //最新底点
       Fractal  newBottom=GetUpToDateBottom(fractals);
       //没有找到底
       if(newBottom.direction==0){
         return;
       }
       int totalOrders= GetPositionsCount(POSITION_TYPE_BUY);
       Print("已有N个多订单.....",totalOrders);
       if(totalOrders>=MaxPostionBuyOrderNum ){
          return;
       }
       int pendingOrderNum= GetPendingOrderCount();
       if(pendingOrderNum>=5){
          Print("已有5个挂单，禁止重复开仓！.....");
          return;
       }
       double open[8], close[8],high[8],low[8];
       if(!LoadBars(open, close, high,low,8)){
            return;
       }
       //止损价格
       double sl=0;
       //止盈价格
       double tp=0;
       
       double newLotSize=InitialLot;
       //当前K线的前一个K
       if(newBottom.originalIndex==1 && newBottom.price<low[0]){
          // 获取最后一笔Buy交易的信息
          ENUM_DEAL_TYPE closedDealType;
          double lastNegativeDealProfit;
          double lastNegativeDealVolume;
          WasLastPositionMegative(_Symbol, closedDealType, lastNegativeDealProfit, lastNegativeDealVolume);
          //如果上一笔交易是亏损的
          if(lastNegativeDealProfit < 0 && closedDealType == DEAL_TYPE_BUY){
            newLotSize = lastNegativeDealVolume * MartingaleMultiplier;    //根据增加系数设定好下笔交易要用的手数
          }
          sl=newBottom.price;
          trade.Buy(newLotSize, _Symbol, high[1], sl, tp, "EA开多单");
      }

}


//做空信号
void CheckSellEntrySignal(){
       static datetime lastCheckTime = 0;
       datetime now = TimeCurrent();
       if(now - lastCheckTime < 10){
            return;
       }
       lastCheckTime = now;
       Fractal fractals[];
       BuildFindFractals(fractals);
       //最新顶点
       Fractal  newTop=GetUpToDateTop(fractals);
       //没有找到底
       if(newTop.direction==0){
         return;
       }
       int totalOrders= GetPositionsCount(POSITION_TYPE_SELL);
       if(totalOrders>=1 ){
          Print("已有1个空单，禁止重复开仓！.....");
          return;
       }
       int pendingOrderNum= GetPendingOrderCount();
       if(pendingOrderNum>=2){
          Print("已有2个挂单，禁止重复开仓！.....");
          return;
       }
       double open[8], close[8],high[8],low[8];
       if(!LoadBars(open, close, high,low,8)){
            return;
       }
        //最新顶点
       Fractal  newBottom=GetUpToDateBottom(fractals);
       
       double emaKEMA[3];
       GetEMAPriceCoseOnBar(emaKEMA,3);
       //止损价格
       double sl=0;
       //止盈价格
       double tp=0;
       //当前K线的前一个K
       
       bool  emaResult= emaKEMA[0]<emaKEMA[1]+90 *_Point; //避免假空
       //空单的左边不能有底信号，此时看震荡
       if(newTop.originalIndex==1 && newBottom.originalIndex!=2 && newTop.price>high[0] && close[1]<open[1] && emaResult){
          trade.Sell(InitialLot, _Symbol, high[1], sl, tp, "EA开空单");
       }
      
       if(newTop.originalIndex==2 &&  close[1]<open[1] && emaResult){
         
          trade.Sell(InitialLot, _Symbol, low[1], open[1], tp, "EA开空单");
       }
       
}





//+------------------------------------------------------------------+
//| 检查多单平仓信号                                                    |
//+------------------------------------------------------------------+
void BuyCheckExitSignal(){
   static datetime lastCheckTime = 0;
   datetime now = TimeCurrent();
   if(now - lastCheckTime < 3){
      return;
   }
   Fractal fractals[];
   BuildFindFractals(fractals);
   double open[8], close[8],high[8],low[8];
   if(!LoadBars(open, close, high,low,8)){
       return;
   }
   double emaKEMA[3];
   GetEMAPriceCoseOnBar(emaKEMA,3);
   for(int i = PositionsTotal() - 1; i >= 0; i--){
       ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
       long magic;
       if(!PositionGetInteger(POSITION_MAGIC, magic)) {
           PrintFormat("异常！EA: %s, 方法：%s, 行号：%d", __FILE__, __FUNCTION__, __LINE__); 
           continue;
       }
       ulong ticket = PositionGetTicket(i);
       string ticketStr=IntegerToString(ticket);
       if(ticket > 0  &&  positionType == POSITION_TYPE_BUY && magic==MagicNumber){
          string symbol = PositionGetString(POSITION_SYMBOL);
          double openPrice = PositionGetDouble(POSITION_PRICE_OPEN); // 获取开仓价格
          double stopLossPrice = PositionGetDouble(POSITION_SL); // 获取止损价格
          double takeProfitPrice = PositionGetDouble(POSITION_TP); // 获取止盈价格
          double profit = PositionGetDouble(POSITION_PROFIT);      //获取当前订单的盈利
          double newSL, newTP;
          //
          Fractal upToDateTop=GetUpToDateTop(fractals);
          //见顶信号出现
          if(upToDateTop.direction!=0 && upToDateTop.originalIndex==1){
             //见顶收阴,并且有明显的均线变化
             if(open[1]>close[1] && emaKEMA[0]+90 *_Point<emaKEMA[1]){
               PrintFormat("做多订单出现见顶信号 并且出现1号k收阴 订单号=%s", ticketStr); 
               trade.PositionClose(ticket);
             }else{
               PrintFormat("做多订单修改止损价格 订单号=%s", ticketStr); 
               trade.PositionModify(ticket,openPrice,takeProfitPrice);
             }
          
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 检查空单平仓信号                                                    |
//+------------------------------------------------------------------+
void SellCheckExitSignal(){
   static datetime lastCheckTime = 0;
   datetime now = TimeCurrent();
   if(now - lastCheckTime < 3){
      return;
   }
   Fractal fractals[];
   BuildFindFractals(fractals);
   double open[8], close[8],high[8],low[8];
   if(!LoadBars(open, close, high,low,8)){
       return;
   }
   double emaKEMA[3];
   GetEMAPriceCoseOnBar(emaKEMA,3);
   for(int i = PositionsTotal() - 1; i >= 0; i--){
       ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
       long magic;
       if(!PositionGetInteger(POSITION_MAGIC, magic)) {
           PrintFormat("异常！EA: %s, 方法：%s, 行号：%d", __FILE__, __FUNCTION__, __LINE__); 
           continue;
       }
       ulong ticket = PositionGetTicket(i);
       string ticketStr=IntegerToString(ticket);
       if(ticket > 0  &&  positionType == POSITION_TYPE_SELL && magic==MagicNumber){
       string symbol = PositionGetString(POSITION_SYMBOL);
       double openPrice = PositionGetDouble(POSITION_PRICE_OPEN); // 获取开仓价格
       double stopLossPrice = PositionGetDouble(POSITION_SL); // 获取止损价格
       double takeProfitPrice = PositionGetDouble(POSITION_TP); // 获取止盈价格
       double profit = PositionGetDouble(POSITION_PROFIT);      //获取当前订单的盈利
       double newSL, newTP;
       //
       Fractal upToDateBottom=GetUpToDateBottom(fractals);
       //见底信号出现
       if(upToDateBottom.direction!=0 && upToDateBottom.originalIndex==1){
          //见底收阳,0号的收盘价大于
          if(open[1]<close[1] && close[0]>close[1]){
            PrintFormat("做空订单出现见底信号 并且出现1号k收阳 订单号=%s", ticketStr); 
            trade.PositionClose(ticket);
          }else{
            trade.PositionModify(ticket,openPrice,takeProfitPrice);
          }
       }
       //如果
       if(profit>0.2){
           PrintFormat("做空订单盈利修改订单止损价为开盘价 订单号=%s", ticketStr); 
          trade.PositionModify(ticket,openPrice,takeProfitPrice);
       }
     }
   }
}




//获取最新底分型的数据
Fractal  GetUpToDateBottom(const Fractal &fractals[]){

    datetime upToDateBottom=0;
    int indexUpToDateBottom=-1;
         
    for (int i = 0; i < ArraySize(fractals); i++){   
       if(fractals[i].direction == -1){
         if(upToDateBottom < fractals[i].time){
           upToDateBottom=fractals[i].time;
           indexUpToDateBottom=i;
         }
       
       }
    }
    if(indexUpToDateBottom!=-1){
      Print("最新底分型 时间: ", TimeToString(fractals[indexUpToDateBottom].time), " | 价格: ", fractals[indexUpToDateBottom].price, " | 原始K的坐标: ", fractals[indexUpToDateBottom].originalIndex);
      return fractals[indexUpToDateBottom];
    }
    // 返回一个空的 Fractal 对象，用 direction=0 表示无效
    Fractal empty;
    empty.time = 0;
    empty.price = 0.0;
    empty.direction = 0;
    return empty;
}



//获取最新顶分型的数据
Fractal  GetUpToDateTop(const Fractal &fractals[]){

    datetime upToDateTop=0;
    int indexUpToDateTop=-1;
         
    for (int i = 0; i < ArraySize(fractals); i++){   
       if(fractals[i].direction == 1){
         if(upToDateTop<fractals[i].time){
           upToDateTop=fractals[i].time;
           indexUpToDateTop=i;
         }
       
       }
    }
    if(indexUpToDateTop!=-1){
      Print("最新顶分型 时间: ", TimeToString(fractals[indexUpToDateTop].time), " | 价格: ", fractals[indexUpToDateTop].price, " | 原始K的坐标: ", fractals[indexUpToDateTop].originalIndex);
      return fractals[indexUpToDateTop];
    }
    
     // 返回一个空的 Fractal 对象，用 direction=0 表示无效
    Fractal empty;
    empty.time = 0;
    empty.price = 0.0;
    empty.direction = 0;
    return empty;

}

void  BuildFindFractals(Fractal &fractals[]){

       MqlRates rates[];
       ArraySetAsSeries(rates, true); // 设置为从右往左索引（0=最新K线）
       CopyRates(_Symbol, PERIOD_M5, 0, barCount, rates);
       // 合并包含关系的K线
       MqlRates mergedRates[];
       MergeKlines(rates, mergedRates);
       // 检测分型（并记录原始K线索引）
       FindFractals(rates, mergedRates, fractals); // 传入原始K线数据
       
        // 在图表上标记分型
       MarkFractalsOnChart(fractals);

}

//+------------------------------------------------------------------+
//| 获取K线对应收盘价格EMA值函数                                            |
//+------------------------------------------------------------------+
void GetEMAPriceCoseOnBar(double &emaKValues[],int barCount){

     // 1. 参数有效性检查
    if(barCount <= 0) {
        Print("错误：barCount必须大于0");
        return;
    }

    // 2. 创建EMA20指标句柄
    int emaHandle = iMA(_Symbol, _Period, EMA_8, 0, MODE_EMA, PRICE_CLOSE);
    
    if(emaHandle == INVALID_HANDLE) {
        Print("EMA20句柄创建失败！错误码=", GetLastError());
        return;
    } else {
        // 3. 准备数据缓冲区
        double buffer[];
        ArraySetAsSeries(buffer, true);  // 时间序列模式(最新数据在数组开头)
        ArrayResize(buffer, barCount);   // 设置缓冲区大小
        
        // 4. 复制数据
        if(CopyBuffer(emaHandle, 0, 0, barCount, buffer) < barCount) {
            Print("复制EMA20值失败！错误码=", GetLastError());
        } else {
            // 5. 将结果存入输出数组
            ArrayResize(emaKValues, barCount);
            for(int i = 0; i < barCount; i++) {
                emaKValues[i] = buffer[i];
            }
        }
    }
}


// 合并包含关系的K线
void MergeKlines(const MqlRates &srcRates[], MqlRates &mergedRates[]){
    ArrayResize(mergedRates, 0);
    if (ArraySize(srcRates) < 1) return;
    
    int trendDirection = 0; // 0=无趋势, 1=上升, -1=下降
    
    // 第一根K线直接加入
    ArrayResize(mergedRates, 1);
    mergedRates[0] = srcRates[0];
    
    for (int i = 1; i < ArraySize(srcRates); i++){
        MqlRates lastMerged = mergedRates[ArraySize(mergedRates)-1];
        MqlRates current = srcRates[i];
        
        bool isContained = (current.high <= lastMerged.high && current.low >= lastMerged.low) || 
                          (current.high >= lastMerged.high && current.low <= lastMerged.low);
        
        if (isContained){
            if (trendDirection == 0){
                if (current.close > lastMerged.close) trendDirection = 1;
                else if (current.close < lastMerged.close) trendDirection = -1;
            }
            
            MqlRates newKline;
            // 上升趋势，取高高
            if (trendDirection >= 0){
                newKline.high = MathMax(lastMerged.high, current.high);
                newKline.low = MathMax(lastMerged.low, current.low);
            // 下降趋势，取低低
            }else {
                newKline.high = MathMin(lastMerged.high, current.high);
                newKline.low = MathMin(lastMerged.low, current.low);
            }
            newKline.open = lastMerged.open;
            newKline.close = current.close;
            newKline.time = lastMerged.time;
            
            mergedRates[ArraySize(mergedRates)-1] = newKline;
        }else {
            ArrayResize(mergedRates, ArraySize(mergedRates)+1);
            mergedRates[ArraySize(mergedRates)-1] = current;
            
            if (current.high > lastMerged.high && current.low > lastMerged.low){
                 trendDirection = 1;
            }else if (current.high < lastMerged.high && current.low < lastMerged.low){
                 trendDirection = -1;
            }  
        }
    }
}

// 检测顶底分型 并记录他原始的坐标K
void FindFractals(const MqlRates &originalRates[], const MqlRates &mergedRates[], Fractal &fractals[]){
     ArrayResize(fractals, 0);
    if (ArraySize(mergedRates) < 3) return;

    
    for (int i = 1; i < ArraySize(mergedRates)-1; i++){
        MqlRates left = mergedRates[i-1];
        MqlRates middle = mergedRates[i];
        MqlRates right = mergedRates[i+1];
        
        // 顶分型：中间K线的高点和低点均高于左右两根
        if (middle.high > left.high && middle.high > right.high && 
            middle.low > left.low && middle.low > right.low){
            // 找到合并后的 middle 对应的原始K线索引
            int originalIndex = FindOriginalIndex(originalRates, middle.time);
            
            Fractal fractal;
            fractal.direction = 1;
            fractal.time = middle.time;
            fractal.price = middle.high;
            fractal.originalIndex = originalIndex;
            
            ArrayResize(fractals, ArraySize(fractals)+1);
            fractals[ArraySize(fractals)-1] = fractal;
        }
        // 底分型：中间K线的低点和高点均低于左右两根
        else if (middle.low < left.low && middle.low < right.low && 
                 middle.high < left.high && middle.high < right.high){
            // 找到合并后的 middle 对应的原始K线索引
            int originalIndex = FindOriginalIndex(originalRates, middle.time);
            
            Fractal fractal;
            fractal.direction = -1;
            fractal.time = middle.time;
            fractal.price = middle.low;
            fractal.originalIndex = originalIndex;
            
            ArrayResize(fractals, ArraySize(fractals)+1);
            fractals[ArraySize(fractals)-1] = fractal;
        }
    }
}

// 根据时间匹配原始K线索引（从右往左，0=最新K线）
int FindOriginalIndex(const MqlRates &originalRates[], datetime targetTime){
    for (int i = 0; i < ArraySize(originalRates); i++)
    {
        if (originalRates[i].time == targetTime)
            return i; // 返回原始K线索引
    }
    return -1; // 未找到（理论上不会发生）
}

// 在图表上标记分型
void MarkFractalsOnChart(const Fractal &fractals[]){
    ObjectsDeleteAll(0, "Fractal_"); // 清除旧标记
    
    for (int i = 0; i < ArraySize(fractals); i++)
    {
        string objName = "Fractal_" + IntegerToString(i);
        
        if (fractals[i].direction == 1) // 顶分型（红色大箭头）
        {
            ObjectCreate(0, objName, OBJ_ARROW_DOWN, 0, fractals[i].time, fractals[i].price);
            ObjectSetInteger(0, objName, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3); // 加粗箭头
            ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 241); // 大箭头样式
            ObjectSetString(0, objName, OBJPROP_TEXT, "顶"); // 添加文字
        }
        else if (fractals[i].direction == -1) // 底分型（绿色大箭头）
        {
            ObjectCreate(0, objName, OBJ_ARROW_UP, 0, fractals[i].time, fractals[i].price);
            ObjectSetInteger(0, objName, OBJPROP_COLOR, clrLime);
            ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3); // 加粗箭头
            ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 242); // 大箭头样式
            ObjectSetString(0, objName, OBJPROP_TEXT, "底"); // 添加文字
        }
    }
    
    ChartRedraw(); // 刷新图表
}

// 打印分型信息到日志
void PrintFractalsInfo(const Fractal &fractals[],MqlRates &mergedRates[])
{
    Print("===== 分型检测结果 =====");
    Print("合并后的K线数量: ", ArraySize(mergedRates));
    Print("检测到的分型数量: ", ArraySize(fractals));
    
    for (int i = 0; i < ArraySize(fractals); i++){
        string type = (fractals[i].direction == 1) ? "顶分型" : "底分型";
        Print(i+1, ": ", type, " | 时间: ", TimeToString(fractals[i].time), " | 价格: ", fractals[i].price, " | 所处的原始K的坐标: ", fractals[i].originalIndex);
    }
}




int GetPositionsCount(ENUM_POSITION_TYPE positionTypeFilter){
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--){
      if(PositionGetSymbol(i) == _Symbol){
         ENUM_POSITION_TYPE currentType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         long magic= PositionGetInteger(POSITION_MAGIC);
         if(currentType == positionTypeFilter && magic == MagicNumber){
            count++;
         }
      }
   }
   return count;
}


void LossExceedingThreshold(){

   static datetime lastCheckTime = 0;
// 当前时间
   datetime now = TimeCurrent();
// 如果距离上次执行不足20秒，则跳过
   if(now - lastCheckTime < 40){
      return;
   }
   lastCheckTime = now;
   double newBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   ulong accountID = AccountInfoInteger(ACCOUNT_LOGIN);
   if(Balance <= 0) {
      return;
   }
   PrintFormat("账户最新结余, 账号ID=%s, 初始资金=%.3f, 最新结余=%.3f",IntegerToString(accountID),Balance ,newBalance);
   double lossPercent=0;
   if(newBalance>Balance){
      lossPercent = (1.0 - equity / newBalance) * 100;
   }else{
      lossPercent = (1.0 - equity / Balance) * 100;
   }
   //PrintFormat("多账户风控检测 禁值==%.3f, 结余=%.3f 亏损==%.2f", equity, balance, lossPercent);
   if(lossPercent >= LossPercent){
      for(int i = PositionsTotal() - 1; i >= 0; i--){
          ulong ticket = PositionGetTicket(i);
          string ticketStr=IntegerToString(ticket);
          if(ticket > 0){
                // 获取魔术码
              long magic;
              if(!PositionGetInteger(POSITION_MAGIC, magic)) {
                  PrintFormat("异常！EA: %s, 方法: %s, 行号: %d - 获取魔术码失败", 
                            __FILE__, __FUNCTION__, __LINE__);
                  continue;
              }
              // 检查是否为本EA持仓
              if(magic != MagicNumber){
                continue;
              } 
               // 平仓并记录结果
              Print("强制平仓！继续平仓 ...：订单编号="+ticketStr);
              trade.PositionClose(ticket);
         }
      }
      
      ExpertRemove(); // 可选：停止EA运行
      return;
   }
   
}


int GetPendingOrderCount(){
    int count = 0;
    for(int i = 0; i < OrdersTotal(); i++){
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket)){
            int type = (int)OrderGetInteger(ORDER_TYPE);
            if(type == ORDER_TYPE_BUY_LIMIT ||
               type == ORDER_TYPE_SELL_LIMIT ||
               type == ORDER_TYPE_BUY_STOP ||
               type == ORDER_TYPE_SELL_STOP ||
               type == ORDER_TYPE_BUY_STOP_LIMIT ||
               type == ORDER_TYPE_SELL_STOP_LIMIT){
                count++;
            }
        }
    }
    return count;
}

void DeleteAllPendingOrders(){
    for(int i = OrdersTotal() - 1; i >= 0; i--){
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            // 过滤当前品种的挂单
            if(OrderGetString(ORDER_SYMBOL) == _Symbol)
            {
                int type = (int)OrderGetInteger(ORDER_TYPE);
                if(type >= ORDER_TYPE_BUY_LIMIT && type <= ORDER_TYPE_SELL_STOP_LIMIT)
                {
                    bool result = trade.OrderDelete(ticket);
                    if(result)
                        Print("挂单删除成功：", ticket);
                    else
                        Print("挂单删除失败：", ticket, " 错误：", GetLastError());
                }
            }
        }
    }
}


//获取最后一笔交易的信息
bool WasLastPositionMegative(string symbol, ENUM_DEAL_TYPE &closedDealType, double &lastMegativeDealProfit, double &lastMegativeDealLot){
    datetime from_date = TimeCurrent() - 60 * 60 * 24 * 100; // 最近100天
    datetime to_date = TimeCurrent() + 60 * 60 * 24 * 1;     // 未来1天
    HistorySelect(from_date, to_date);

    int total_deals = HistoryDealsTotal(); //交易记录的总数
    ulong ticket_history_deal = 0;
    for(int i = total_deals - 1; i >= 0; i--){
        if(ticket_history_deal = HistoryDealGetTicket(i) > 0){
            if(m_deal.SelectByIndex(i)){
                if(m_deal.Symbol() == symbol && m_deal.Magic() == MagicNumber && m_deal.Entry() == DEAL_ENTRY_OUT ){
                    lastMegativeDealProfit = m_deal.Profit();
                    lastMegativeDealLot = m_deal.Volume();
                    return true;
                }
            }
        }
    }
    return false;
}




bool LoadBars(double &open[], double &close[],double &high[],double &low[], int count){
// 调整数组大小
   ArrayResize(open, count);
   ArrayResize(close, count);
   ArrayResize(high, count);
   ArrayResize(low, count);

   double closePrice0=iClose(_Symbol,Current_TimeFrame,0);
   double closePrice1=iClose(_Symbol,Current_TimeFrame,1);
   double closePrice2=iClose(_Symbol,Current_TimeFrame,2);
   double closePrice3=iClose(_Symbol,Current_TimeFrame,3);
   double closePrice4=iClose(_Symbol,Current_TimeFrame,4);
   double closePrice5=iClose(_Symbol,Current_TimeFrame,5);
   double closePrice6=iClose(_Symbol,Current_TimeFrame,6);
   double closePrice7=iClose(_Symbol,Current_TimeFrame,7);


   close[0]=closePrice0;
   close[1]=closePrice1;
   close[2]=closePrice2;
   close[3]=closePrice3;
   close[4]=closePrice4;
   close[5]=closePrice5;
   close[6]=closePrice6;
   close[7]=closePrice7;

   double openPrice0=iOpen(_Symbol,Current_TimeFrame,0);
   double openPrice1=iOpen(_Symbol,Current_TimeFrame,1);
   double openPrice2=iOpen(_Symbol,Current_TimeFrame,2);
   double openPrice3=iOpen(_Symbol,Current_TimeFrame,3);
   double openPrice4=iOpen(_Symbol,Current_TimeFrame,4);
   double openPrice5=iOpen(_Symbol,Current_TimeFrame,5);
   double openPrice6=iOpen(_Symbol,Current_TimeFrame,6);
   double openPrice7=iOpen(_Symbol,Current_TimeFrame,7);

   open[0]=openPrice0;
   open[1]=openPrice1;
   open[2]=openPrice2;
   open[3]=openPrice3;
   open[4]=openPrice4;
   open[5]=openPrice5;
   open[6]=openPrice6;
   open[7]=openPrice7;


   double low0=iLow(_Symbol,Current_TimeFrame,0);
   double low1=iLow(_Symbol,Current_TimeFrame,1);
   double low2=iLow(_Symbol,Current_TimeFrame,2);
   double low3=iLow(_Symbol,Current_TimeFrame,3);
   double low4=iLow(_Symbol,Current_TimeFrame,4);
   double low5=iLow(_Symbol,Current_TimeFrame,5);
   double low6=iLow(_Symbol,Current_TimeFrame,6);
   double low7=iLow(_Symbol,Current_TimeFrame,7);

   low[0]=low0;
   low[1]=low1;
   low[2]=low2;
   low[3]=low3;
   low[4]=low4;
   low[5]=low5;
   low[6]=low6;
   low[7]=low7;


   double high0=iHigh(_Symbol,Current_TimeFrame,0);
   double high1=iHigh(_Symbol,Current_TimeFrame,1);
   double high2=iHigh(_Symbol,Current_TimeFrame,2);
   double high3=iHigh(_Symbol,Current_TimeFrame,3);
   double high4=iHigh(_Symbol,Current_TimeFrame,4);
   double high5=iHigh(_Symbol,Current_TimeFrame,5);
   double high6=iHigh(_Symbol,Current_TimeFrame,6);
   double high7=iHigh(_Symbol,Current_TimeFrame,7);

   high[0]=high0;
   high[1]=high1;
   high[2]=high2;
   high[3]=high3;
   high[4]=high4;
   high[5]=high5;
   high[6]=high6;
   high[7]=high7;

   return true;
}
