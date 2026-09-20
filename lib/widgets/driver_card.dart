import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:orderly_app/models/driver.dart';
import 'package:orderly_app/theme/app_theme.dart';
import 'package:orderly_app/utils/formatters.dart';
import 'package:orderly_app/widgets/stat_tile.dart';

/// بطاقة عامل التوصيل — تصميم Dark Mode احترافي
class DriverCard extends StatefulWidget {
  const DriverCard({
    super.key,
    required this.driver,
    this.onTap,
    this.onRegisterOrder,
    this.onLongPress,
  });

  final Driver driver;
  final VoidCallback? onTap;
  final VoidCallback? onRegisterOrder;
  final VoidCallback? onLongPress;

  @override
  State<DriverCard> createState() => _DriverCardState();
}

class _DriverCardState extends State<DriverCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.97,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = _ctrl;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String name =
        widget.driver.name.isEmpty ? 'بدون اسم' : widget.driver.name;

    return GestureDetector(
      onTapDown: (_) => _ctrl.reverse(),
      onTapUp: (_) {
        _ctrl.forward();
        widget.onTap?.call();
      },
      onTapCancel: () => _ctrl.forward(),
      onLongPress: widget.onLongPress,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          key: ValueKey<String>('driver-card-$name'),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ── رأس البطاقة ──────────────────────────────────────
              _buildHeader(name),
              // ── الإحصائيات ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: StatTile(
                            label: 'عدد الطلبات',
                            value: formatNumber(widget.driver.ordersCount),
                            icon: Icons.receipt_long_rounded,
                            color: AppColors.primary,
                            valueKey:
                                ValueKey<String>('card-orders-$name'),
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatTile(
                            label: 'إجمالي المبالغ',
                            value: formatAmount(
                                widget.driver.totalOrdersAmount),
                            icon: Icons.payments_rounded,
                            color: AppColors.info,
                            valueKey: ValueKey<String>('card-total-$name'),
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: StatTile(
                            label: 'أجرة العامل',
                            value: formatAmount(widget.driver.wage),
                            icon: Icons.savings_rounded,
                            color: AppColors.gold,
                            valueKey: ValueKey<String>('card-wage-$name'),
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatTile(
                            label: 'صافي المطعم',
                            value: formatAmount(
                                widget.driver.netAmountToRestaurant),
                            icon: Icons.storefront_rounded,
                            color: AppColors.success,
                            valueKey: ValueKey<String>('card-net-$name'),
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                    if (widget.driver.hasZeroWageOrders) ...<Widget>[
                      const SizedBox(height: 8),
                      _ZeroWageBadge(driver: widget.driver, name: name),
                    ],
                    const SizedBox(height: 12),
                    // ── زر تسجيل طلب ─────────────────────────────
                    _buildRegisterButton(name),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[Color(0xFF0F2740), Color(0xFF1A3050)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: <Widget>[
          // أفاتار
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              name.substring(0, 1),
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // الاسم والأجرة
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (widget.driver.pin.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                AppColors.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          '#${widget.driver.pin}',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'أجرة الطلب: ${formatAmount(widget.driver.wagePerOrder)}',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // سهم العرض
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: const Icon(
              Icons.chevron_left_rounded,
              size: 20,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterButton(String name) {
    return GestureDetector(
      onTap: widget.onRegisterOrder,
      child: Container(
        key: ValueKey<String>('register-order-$name'),
        height: 46,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.add_circle_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              'تسجيل طلب',
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── شارة الطلبات بدون أجرة ────────────────────────────────────────────────

class _ZeroWageBadge extends StatelessWidget {
  const _ZeroWageBadge({required this.driver, required this.name});

  final Driver driver;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_rounded,
              size: 14, color: AppColors.warning),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${formatNumber(driver.zeroWageOrdersCount)} طلب بدون أجرة (ماستر كارد/استلام مباشر/خاص)',
              key: ValueKey<String>('card-zerowage-$name'),
              style: GoogleFonts.cairo(
                fontSize: 11,
                color: AppColors.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
