import 'dart:convert';
import 'package:storeos_api_contracts/api_contracts.dart';

String renderLayoutPrint(LayoutViewDto view) {
  final revision = view.revision!;
  String escape(Object? value) =>
      const HtmlEscape().convert(value?.toString() ?? '');
  final b = StringBuffer(
    '<!doctype html><html lang="de"><head><meta charset="utf-8"><title>${escape(view.fixture.name)}</title><style>@page{size:A4 landscape;margin:12mm}body{font:12pt sans-serif;color:#000;background:#fff}h1{font-size:20pt}h2{font-size:15pt;break-after:avoid}table{width:100%;border-collapse:collapse;table-layout:fixed}th,td{border:1px solid #555;padding:5px;text-align:left;overflow-wrap:anywhere}thead{display:table-header-group}tr{break-inside:avoid}.historical{border:2px solid #000;padding:8px}footer{margin-top:12px;font-size:10pt}</style></head><body><h1>${escape(view.fixture.name)} · ${escape(revision.content.title)}</h1>',
  );
  if (view.historical) {
    b.write('<p class="historical">Historische Zuweisung</p>');
  }
  b.write(
    '<p>Revision ${revision.revisionNumber} · veröffentlicht ${escape(revision.json['publishedAt'])}<br>Zuweisung ${escape(view.assignment!.id)}</p>',
  );
  for (final zone in revision.content.zones) {
    b.write(
      '<h2>${escape(zone.label)}</h2><table><colgroup><col style="width:8%"><col style="width:80%"><col style="width:12%"></colgroup><thead><tr><th colspan="3">${escape(zone.label)}</th></tr><tr><th>Position</th><th>Artikel · SKU · Barcode</th><th>Facings</th></tr></thead><tbody>',
    );
    for (var i = 0; i < zone.placements.length; i++) {
      final p = zone.placements[i];
      final matches = view.articles.where((a) => a['id'] == p.articleId);
      final a = matches.isEmpty ? null : matches.first;
      b.write(
        '<tr><td>${i + 1}</td><td>${escape(a?['name'] ?? p.articleId)}<br>${escape(a?['sku'])} · ${escape(a?['barcode'])}${a != null && (a['isActive'] != true || a['assortmentIsActive'] != true) ? '<br>Warnung: Artikel/Sortiment derzeit inaktiv' : ''}</td><td>${p.facings ?? ''}</td></tr>',
      );
    }
    b.write('</tbody></table>');
  }
  b.write(
    '<footer>Erzeugt ${escape(view.queriedAt.toUtc().toIso8601String())}. Artikelbezeichnungen entsprechen dem aktuellen Datenstand bei Erzeugung. Layout und Zuweisung bleiben fest zugeordnet.</footer></body></html>',
  );
  return b.toString();
}
