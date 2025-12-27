# D-Basket EA - Quick Start Guide

## Installation

### 1. Copy Files to MT5

Copy the entire `MQL5` folder structure to your MetaTrader 5 data directory:

**Windows**: `C:\Users\[YourName]\AppData\Roaming\MetaQuotes\Terminal\[Instance]\MQL5\`

**File Structure**:
```
MQL5/
├── Experts/
│   └── DBasketEA.mq5
└── Include/
    └── DBasket/
        ├── DBasket_Defines.mqh
        ├── DBasket_Structures.mqh
        ├── DBasket_Logger.mqh
        ├── DBasket_CorrelationEngine.mqh
        ├── DBasket_SignalEngine.mqh
        ├── DBasket_TradeWrapper.mqh
        ├── DBasket_PositionManager.mqh
        └── DBasket_RiskManager.mqh
```

### 2. Compile in MetaEditor

1. Open MetaEditor (F4 in MT5)
2. Navigate to `Experts/DBasketEA.mq5`
3. Click Compile (F7)
4. Verify: **0 errors, 0 warnings** ✅

### 3. Attach to Chart

1. Open AUDCAD chart (any timeframe, M15 or H1 recommended)
2. Drag `DBasketEA` from Navigator onto chart
3. Configure parameters (see below)
4. Enable AutoTrading (Ctrl+E)

---

## Essential Parameters

### Minimum Configuration

```
Symbol Suffix: [leave blank or enter broker suffix like ".m"]
Entry Z-Score: 2.5
Exit Z-Score: 0.5
Min Correlation: 0.75
Fixed Lot Size: 0.01
Max Drawdown: 15.0
Daily Loss Limit: 100.0
```

### Critical Settings

> ⚠️ **MUST CONFIGURE**
> 
> - **Symbol Suffix**: If your broker uses suffixes (e.g., AUDCAD.m), enter it here
> - **Magic Number**: Change if running multiple EAs
> - **Max Drawdown**: Set according to your risk tolerance

---

## Pre-Flight Checklist

Before running the EA, verify:

- [ ] ✅ **Hedging account** (not netting) - EA will fail on netting accounts
- [ ] ✅ All 3 symbols available: AUDCAD, NZDCAD, AUDNZD
- [ ] ✅ AutoTrading enabled in MT5 (Ctrl+E)
- [ ] ✅ EA allowed to trade (Tools → Options → Expert Advisors)
- [ ] ✅ Sufficient margin for 3 positions
- [ ] ✅ Spreads reasonable (< 3 pips per symbol)

---

## First Backtest

### Strategy Tester Setup

1. **Symbol**: AUDCAD
2. **Timeframe**: M15 or H1
3. **Period**: 2023.01.01 - 2025.01.01 (1 year minimum)
4. **Model**: Every tick based on real ticks
5. **Deposit**: 10,000 (or your account size)
6. **Leverage**: 1:100 (or your broker's leverage)

### Expected Results

- **Trade Count**: 50-200 baskets per year (depends on parameters)
- **Win Rate**: Target > 65%
- **Profit Factor**: Target > 1.3
- **Max Drawdown**: Should stay below configured limit

### Visual Mode

Enable visual mode to see:
- When baskets open/close
- Z-score values in real-time
- Circuit breaker status
- Performance metrics on chart

---

## Understanding the Display

The EA shows real-time metrics on the chart:

```
=== D-Basket EA Risk Monitor ===
Status: NORMAL
Net P/L: $125.50 (1.3%)
Daily P/L: $45.20
Drawdown: 3.2% (Max: 5.8%)
Baskets: 12 | Win Rate: 75.0%
Consecutive Losses: 0
```

### Status Indicators

- **NORMAL**: Trading allowed, all systems operational
- **WARNING**: Risk levels elevated, warnings logged
- **HALTED**: Circuit breaker tripped, trading stopped

---

## Common Scenarios

### Scenario 1: EA Opens a Basket

**What happens**:
1. Z-score exceeds entry threshold (e.g., -2.7)
2. All 8 filters pass
3. EA opens 3 positions simultaneously:
   - AUDNZD: BUY 0.01 lots
   - AUDCAD: SELL 0.01 lots
   - NZDCAD: BUY 0.01 lots

**What to check**:
- All 3 positions opened successfully
- Magic number matches on all positions
- Comment shows basket ID (e.g., "DBasket_1")

### Scenario 2: EA Closes a Basket

**What happens**:
1. Z-score returns to exit threshold (e.g., -0.3)
2. EA closes all 3 positions
3. P&L is recorded and metrics updated

**What to check**:
- All 3 positions closed
- Win/loss recorded correctly
- Metrics updated on chart

### Scenario 3: Circuit Breaker Trips

**What happens**:
1. Drawdown reaches 15% (or configured limit)
2. EA status changes to "HALTED"
3. No new baskets will open
4. Existing basket may be closed (emergency exit)

**What to do**:
- Review what caused the drawdown
- Check if parameters need adjustment
- Manually reset circuit breaker if appropriate
- Consider reducing risk parameters

---

## Troubleshooting

### EA Not Opening Trades

**Check**:
1. Circuit breaker status (should be NORMAL)
2. Current z-score (use visual mode to see)
3. Correlation level (must be > min threshold)
4. Spreads (must be < max threshold)
5. Trading hours (must be within configured window)
6. Logs for filter rejection reasons

### Partial Basket Opened

**What happened**:
- One or two legs opened, but not all three
- EA automatically rolled back (closed opened positions)

**Check**:
- Logs for error messages
- Broker execution quality
- Margin availability
- Symbol tradability

### High Drawdown

**Actions**:
1. Stop EA immediately
2. Review recent trades
3. Check if correlation broke down
4. Consider more conservative parameters:
   - Increase entry z-score (e.g., 3.0)
   - Increase min correlation (e.g., 0.80)
   - Reduce lot size
   - Lower max drawdown limit

---

## Parameter Optimization

### Optimization Ranges

Use Strategy Tester's optimization feature:

| Parameter | Min | Max | Step |
|-----------|-----|-----|------|
| Entry Z-Score | 2.0 | 3.5 | 0.25 |
| Exit Z-Score | 0.3 | 1.0 | 0.1 |
| Min Correlation | 0.70 | 0.85 | 0.05 |
| Lookback Period | 150 | 350 | 50 |

### Optimization Criterion

The EA's `OnTester()` function returns a custom score:

```
score = (profit / drawdown) × profit_factor × win_rate
```

This prioritizes:
- Risk-adjusted returns
- Consistent profitability
- High win rate

---

## Risk Management

### Circuit Breaker Triggers

| Condition | Warning | Trip |
|-----------|---------|------|
| Drawdown | 8% | 15% |
| Daily Loss | - | $100 or 5% |
| Margin Level | 500% | 200% |
| Consecutive Losses | - | 6 |

### Manual Intervention

**When to intervene**:
- Circuit breaker trips repeatedly
- Win rate drops below 50%
- Correlation between pairs breaks down
- Broker execution quality degrades

**How to intervene**:
1. Stop EA
2. Close any open baskets manually
3. Review parameters
4. Restart with adjusted settings

---

## Best Practices

### 1. Start Small
- Begin with minimum lot size (0.01)
- Test on demo account for 1+ month
- Gradually increase lot size after validation

### 2. Monitor Daily
- Check circuit breaker status
- Review daily P&L
- Verify correlation remains stable
- Check for error logs

### 3. Regular Optimization
- Reoptimize parameters quarterly
- Use walk-forward analysis
- Compare live results to backtest

### 4. Broker Selection
- Choose broker with tight spreads
- Ensure hedging is allowed
- Verify fast execution (< 500ms)
- Check commission structure

---

## Support

### Log Files

Enable file logging for detailed records:
```
Log Level: INFO (or DEBUG for troubleshooting)
Log to File: true
```

Logs saved to: `MQL5/Files/DBasket_[date].log`

### Documentation

- **README.md** - User guide and installation
- **TECHNICAL_DOCUMENTATION.md** - Architecture and diagrams
- **DEVELOPMENT_SUMMARY.md** - Project overview

### Common Questions

**Q: Can I run this on a netting account?**  
A: No, hedging account is mandatory. The EA will fail initialization on netting accounts.

**Q: How many trades per week?**  
A: Typically 2-10 signals per week at default parameters. Depends on market volatility.

**Q: What's the minimum account size?**  
A: Recommended minimum $1,000 for 0.01 lot size with proper risk management.

**Q: Can I run multiple instances?**  
A: Yes, but use different magic numbers for each instance.

---

## Next Steps

1. ✅ Install and compile EA
2. ⏳ Run backtest on 1 year of data
3. ⏳ Optimize parameters
4. ⏳ Deploy to demo account
5. ⏳ Monitor for 1+ month
6. ⏳ Consider live deployment

---

## 📄 License & Copyright

**Copyright © 2025 Dineth Pramodya**  
**Website**: [www.dineth.lk](https://www.dineth.lk)  
**All rights reserved.**

---

*Last Updated: December 28, 2025*  
*Developed by: Dineth Pramodya*  
*For detailed technical information, see TECHNICAL_DOCUMENTATION.md*
