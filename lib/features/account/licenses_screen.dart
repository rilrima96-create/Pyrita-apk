import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// Attribution / Licenses screen.
///
/// Юридическое требование — мы используем open-source библиотеки,
/// каждая под своей лицензией. Конкретно:
///
///   * Xray-core (MPL-2.0) — VPN-движок. File-level copyleft означает что
///     если бы мы модифицировали сам Xray, наши изменения должны быть
///     под MPL-2.0. Мы Xray НЕ модифицируем — только используем как
///     library через flutter_v2ray_client wrapper. Наш application code
///     остаётся под нашей лицензией (proprietary). MPL-2.0 require
///     attribution и ссылку на source code — этот screen делает это.
///
///   * flutter_v2ray_client (MIT, amir-zr) — Flutter wrapper.
///     Требует include copyright notice — этот screen это покрывает.
///
///   * Прочие deps (Riverpod / go_router / Dio / etc.) — все BSD/Apache/MIT,
///     standard Flutter ecosystem. Полные license texts через
///     Settings → About app в Android (auto-generated).
class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PyDS.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: PyDS.gradBg),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _TopBar(onBack: () => context.pop())),
              SliverToBoxAdapter(child: const SizedBox(height: PyDS.sp3)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                    horizontal: PyDS.sp4 + 2),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    Text(
                      'Открытые библиотеки',
                      style: PyDS.font(
                        size: 22,
                        weight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: PyDS.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pyrita использует open-source компоненты. Каждый — '
                      'под своей лицензией. Ниже исходники и условия '
                      'использования.',
                      style: PyDS.font(
                        size: 12.5,
                        weight: FontWeight.w500,
                        height: 1.5,
                        color: PyDS.textSoft,
                      ),
                    ),
                    const SizedBox(height: PyDS.sp5),
                    _LicenseCard(
                      name: 'Xray-core',
                      version: 'v26.4.17',
                      role: 'VPN-движок — обрабатывает VLESS + Reality',
                      license: 'Mozilla Public License 2.0',
                      copyright: 'Copyright © XTLS / Project X contributors',
                      sourceUrl: 'https://github.com/XTLS/Xray-core',
                    ),
                    _LicenseCard(
                      name: 'flutter_v2ray_client',
                      version: 'v3.2.0',
                      role: 'Flutter wrapper над Xray для Android',
                      license: 'MIT License',
                      copyright: 'Copyright © 2025 Amir Ziari',
                      sourceUrl:
                          'https://github.com/amir-zr/flutter_v2ray_client',
                    ),
                    _LicenseCard(
                      name: 'tun2socks',
                      version: 'bundled',
                      role: 'TUN ↔ SOCKS5 bridge для Android VpnService',
                      license: 'MIT License',
                      copyright: 'Copyright © xjasonlyu / contributors',
                      sourceUrl: 'https://github.com/xjasonlyu/tun2socks',
                    ),
                    _LicenseCard(
                      name: 'Flutter framework',
                      version: '3.41.9',
                      role: 'UI framework',
                      license: 'BSD-3-Clause',
                      copyright: 'Copyright © Google LLC',
                      sourceUrl: 'https://github.com/flutter/flutter',
                    ),
                    _LicenseCard(
                      name: 'Riverpod',
                      version: '2.x',
                      role: 'State management',
                      license: 'MIT License',
                      copyright: 'Copyright © Remi Rousselet',
                      sourceUrl: 'https://github.com/rrousselGit/riverpod',
                    ),
                    const SizedBox(height: PyDS.sp4),
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          showLicensePage(
                            context: context,
                            applicationName: 'Pyrita',
                            applicationVersion: '0.1.10',
                          );
                        },
                        icon: const Icon(
                          Icons.list_alt_outlined,
                          color: PyDS.goldLight,
                          size: 18,
                        ),
                        label: Text(
                          'Полный список зависимостей',
                          style: PyDS.font(
                            size: 13,
                            weight: FontWeight.w600,
                            color: PyDS.goldLight,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: PyDS.sp6),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PyDS.sp3,
        PyDS.sp3,
        PyDS.sp4 + 2,
        PyDS.sp2,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: PyDS.text),
            tooltip: 'Назад',
          ),
          const SizedBox(width: PyDS.sp2),
          Text(
            'Лицензии',
            style: PyDS.font(
              size: 17,
              weight: FontWeight.w700,
              color: PyDS.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseCard extends StatelessWidget {
  const _LicenseCard({
    required this.name,
    required this.version,
    required this.role,
    required this.license,
    required this.copyright,
    required this.sourceUrl,
  });

  final String name;
  final String version;
  final String role;
  final String license;
  final String copyright;
  final String sourceUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: PyDS.sp2 + 2),
      padding: const EdgeInsets.all(PyDS.sp4),
      decoration: BoxDecoration(
        gradient: PyDS.gradCard,
        borderRadius: BorderRadius.circular(PyDS.rMd),
        border: Border.all(color: PyDS.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: PyDS.font(
                    size: 14.5,
                    weight: FontWeight.w800,
                    color: PyDS.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                version,
                style: PyDS.font(
                  size: 11,
                  weight: FontWeight.w500,
                  color: PyDS.textFaint,
                  mono: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            role,
            style: PyDS.font(
              size: 12,
              weight: FontWeight.w500,
              height: 1.4,
              color: PyDS.textSoft,
            ),
          ),
          const SizedBox(height: PyDS.sp2),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: PyDS.bg,
              borderRadius: BorderRadius.circular(PyDS.rXs),
              border: Border.all(color: PyDS.strokeSoft),
            ),
            child: Text(
              license,
              style: PyDS.font(
                size: 10.5,
                weight: FontWeight.w700,
                letterSpacing: 0.3,
                color: PyDS.goldLight,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            copyright,
            style: PyDS.font(
              size: 10.5,
              weight: FontWeight.w500,
              color: PyDS.textFaint,
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => Clipboard.setData(ClipboardData(text: sourceUrl)),
            child: Row(
              children: [
                const Icon(Icons.link, size: 12, color: PyDS.textFaint),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    sourceUrl,
                    style: PyDS.font(
                      size: 10.5,
                      weight: FontWeight.w500,
                      color: PyDS.textSoft,
                      mono: true,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
