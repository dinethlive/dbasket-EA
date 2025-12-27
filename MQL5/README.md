# D-Basket EA - Correlation Hedging Expert Advisor

A production-level MetaTrader 5 Expert Advisor implementing a three-pair correlation hedging strategy for AUDCAD, NZDCAD, and AUDNZD.

## Overview

This EA exploits the mathematical relationship between three currency pairs:

```
AUDNZD ≈ AUDCAD / NZDCAD
```

When the synthetic ratio (AUDCAD/NZDCAD) diverges from the actual AUDNZD price, the EA enters a hedged three-leg basket expecting mean reversion.

## Strategy Summary

- **Long Basket** (when AUDNZD appears underpriced):
  - Long AUDNZD
  - Short AUDCAD
  - Long NZDCAD

- **Short Basket** (when AUDNZD appears overpriced):
  - Short AUDNZD
  - Long AUDCAD
  - Short NZDCAD

## Features

- **Multi-Symbol Management**: Single EA instance manages all three symbols internally
- **Z-Score Based Signals**: Statistical divergence detection using rolling correlation and z-score
- **Multi-Stage Signal Filtering**: 8 validation stages including spread, correlation, volatility, and time filters
- **Coordinated Basket Execution**: All 3 legs executed atomically with rollback on failure
- **Circuit Breaker System**: Automatic trading halt on drawdown, daily loss, or margin warnings
- **State Recovery**: Recovers basket state after EA restart
- **Performance Tracking**: Real-time metrics with chart display

## Requirements

> ⚠️ **CRITICAL: Hedging Account Required**
> 
> This EA requires a broker account with hedging enabled. Netting accounts will NOT work.

- MetaTrader 5 platform
- Hedging account type
- All three symbols available: AUDCAD, NZDCAD, AUDNZD
- Recommended: VPS for 24/5 operation

## Installation

1. Copy `MQL5/Experts/DBasketEA.mq5` to your `MQL5/Experts/` folder
2. Copy the entire `MQL5/Include/DBasket/` folder to your `MQL5/Include/` folder
3. Open MetaEditor and compile `DBasketEA.mq5`
4. Attach EA to any chart (AUDCAD recommended)

## File Structure

```
MQL5/
├── Experts/
│   └── DBasketEA.mq5           # Main EA file
└── Include/
    └── DBasket/
        ├── DBasket_Defines.mqh           # Constants & enumerations
        ├── DBasket_Structures.mqh        # Data structures
        ├── DBasket_Logger.mqh            # Logging utility
        ├── DBasket_CorrelationEngine.mqh # Correlation & z-score calculation
        ├── DBasket_SignalEngine.mqh      # Signal generation & filtering
        ├── DBasket_TradeWrapper.mqh      # Trade execution wrapper
        ├── DBasket_PositionManager.mqh   # Basket position management
        └── DBasket_RiskManager.mqh       # Risk management & circuit breaker
```

## Input Parameters

### Symbol Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| Symbol Suffix | "" | Broker symbol suffix (e.g., ".m", "_sb") |

### Correlation Engine
| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| Lookback Period | 250 | 50-1000 | Bars for correlation/z-score calculation |
| Cache Update | 30 | 10-300 | Seconds between recalculations |

### Signal Generation
| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| Entry Z-Score | 2.5 | 1.5-5.0 | Minimum z-score for entry |
| Exit Z-Score | 0.5 | 0.0-2.0 | Z-score for mean reversion exit |
| Min Correlation | 0.75 | 0.50-0.95 | Minimum AUDCAD-NZDCAD correlation |
| Max Spread | 3.0 | 0.5-10.0 | Maximum spread (pips) per symbol |

### Risk Management
| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| Fixed Lot Size | 0.01 | Min-Max | Lot size per basket leg |
| Risk % | 1.0 | 0.1-10.0 | Risk % per basket (if dynamic sizing) |
| Max Drawdown | 15.0 | 5-50 | Circuit breaker threshold (%) |
| Daily Loss Limit | $100 | 0-∞ | Daily loss limit in account currency |
| Max Holding Hours | 24 | 1-168 | Maximum basket hold time |
| Take Profit | $10 | 0-∞ | Basket take profit amount |
| Stop Loss | $15 | 0-∞ | Basket stop loss amount |

### Trading Hours
| Parameter | Default | Description |
|-----------|---------|-------------|
| Start Hour | 0 | Trading window start (broker time) |
| End Hour | 23 | Trading window end (broker time) |
| Avoid Rollover | true | Skip trading near rollover |

## Signal Logic

### Entry Conditions (all must pass)
1. ✓ Correlation data is valid
2. ✓ No basket currently open
3. ✓ Within trading hours
4. ✓ Not in rollover period
5. ✓ All symbol spreads below threshold
6. ✓ Primary correlation above minimum
7. ✓ Volatility not excessive
8. ✓ |Z-Score| exceeds entry threshold

### Exit Conditions (any triggers close)
1. Z-score returns to exit threshold (mean reversion)
2. Basket P&L exceeds take profit
3. Basket P&L exceeds stop loss
4. Maximum holding time reached
5. Correlation drops below critical level (0.5)

## Risk Management

### Circuit Breaker Triggers
| Condition | Warning | Trip (Halt Trading) |
|-----------|---------|---------------------|
| Drawdown | 60% of max | Max drawdown reached |
| Daily Loss | - | Daily limit exceeded |
| Margin Level | 500% | Below 200% |
| Consecutive Losses | - | 6 or more |

### Emergency Exit
Immediately closes all positions when:
- Margin level drops below 150%
- System detects critical error

## Backtesting

1. Open Strategy Tester in MT5
2. Select `DBasketEA.mq5`
3. Choose AUDCAD symbol (EA manages others internally)
4. Set timeframe (M15 or H1 recommended)
5. Select "Every tick based on real ticks" for accuracy
6. Set deposit and leverage matching your live account
7. Run test for minimum 1 year of data

### Optimization Tips
- The `OnTester()` function returns a custom score optimizing for:
  - Risk-adjusted return (profit/drawdown)
  - Win rate > 65%
  - Profit factor > 1.3
  - Minimum 20 trades

## Monitoring

The EA displays real-time metrics on the chart:
- Current status (NORMAL/WARNING/HALTED)
- Net P&L and percentage
- Daily P&L
- Current and maximum drawdown
- Basket count and win rate
- Consecutive losses

## Logging

Configurable log levels:
- **ERROR**: Critical errors only
- **WARNING**: Errors + warnings
- **INFO**: Normal operations (recommended)
- **DEBUG**: Full detail for troubleshooting

Enable file logging for persistent records.

## Troubleshooting

### "Hedging account required" error
Your broker account is in netting mode. Contact your broker to switch to a hedging account.

### EA not opening trades
Check:
1. Risk limits not breached (circuit breaker)
2. Current Z-score meets entry threshold
3. Spreads within limits
4. Within trading hours
5. Correlation above minimum

### Partial basket
If a basket is only partially filled, the EA will:
1. Attempt to complete the basket
2. If unable, close the opened legs
3. Log the issue for review

## Disclaimer

> ⚠️ **Risk Warning**
>
> Trading forex involves significant risk. This EA is provided for educational purposes. Past performance does not guarantee future results. Always test thoroughly on demo accounts before live trading. Never risk more than you can afford to lose.

## License

---

## ?? License & Copyright

**Copyright � 2025 Dineth Pramodya**  
**Website**: [www.dineth.lk](https://www.dineth.lk)  
**All rights reserved.**

---

*Last Updated: December 28, 2025*  
*Developed by: Dineth Pramodya*