-- 生産者マスタ再取り込みSQL
-- 元ファイル: G:\マイドライブ\にんにく管理\令和8年\にんにく仕入れ管理表 エイト 令和8年産.xlsm
-- シート: 仕入先一覧表
-- A列/B列 -> producer_source='A', producer_no=3桁
-- D列/E列 -> producer_source='D', producer_no=2桁
-- 注意: public.producers を一度空にしてから再投入します。

begin;

create table if not exists public.app_settings (
  setting_key text primary key,
  setting_value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.app_settings enable row level security;
drop policy if exists anon_read_app_settings on public.app_settings;
create policy anon_read_app_settings on public.app_settings for select to anon using (true);
grant select on public.app_settings to anon;

alter table public.producers
  add column if not exists producer_source text not null default 'A';

alter table public.producers
  drop constraint if exists producers_producer_source_check;

alter table public.producers
  add constraint producers_producer_source_check
  check (producer_source in ('A', 'D'));

alter table public.producers
  drop constraint if exists producers_pkey;

truncate table public.producers;

insert into public.producers (producer_source, producer_no, producer_name)
values
  ('A', '001', '田中 継美'),
  ('A', '002', '山崎 淑弘'),
  ('A', '003', '橋本 義一'),
  ('A', '004', '東 幸信'),
  ('A', '005', '沢居 貴之'),
  ('A', '006', '大鹿 憲一'),
  ('A', '007', '長谷川孝弥'),
  ('A', '008', '中村 信男'),
  ('A', '009', '長谷川 一弥'),
  ('A', '010', '樋口 友勝'),
  ('A', '011', '川村 利次'),
  ('A', '012', '中平観光農園'),
  ('A', '013', '石井 ツマ子'),
  ('A', '014', '織笠翔吾'),
  ('A', '015', '浜田 正則'),
  ('A', '016', '鶴ヶ崎 長福'),
  ('A', '017', '-'),
  ('A', '018', '坂下光弘'),
  ('A', '019', '母良田哲'),
  ('A', '020', '高屋光男'),
  ('A', '021', '-'),
  ('A', '022', '野田淳一'),
  ('A', '023', '豊川忠男'),
  ('A', '024', '佐藤哲'),
  ('A', '025', '小林弘'),
  ('A', '026', '田島誠'),
  ('A', '027', '(株)さとうファーム'),
  ('A', '028', '-'),
  ('A', '029', '沼岡カヨ'),
  ('A', '030', '佐々木秀幸'),
  ('A', '031', '今泉良七'),
  ('A', '032', '佐々木隆博'),
  ('A', '033', '関口栄一'),
  ('A', '034', '小笠原彰真'),
  ('A', '035', '小川鐡男'),
  ('A', '036', '久保田崇博'),
  ('A', '037', '佐々木芳也'),
  ('A', '038', '山田ニカ'),
  ('A', '039', '四木誉将'),
  ('A', '040', '平舘龍太郎'),
  ('A', '041', '鶴田隆雄'),
  ('A', '042', '高村寛'),
  ('A', '043', '佐々木一幸'),
  ('A', '044', '大久保正一(返却)'),
  ('A', '045', '米田イト'),
  ('A', '046', '(株)ファームランド小林'),
  ('A', '047', '佐々木求'),
  ('A', '048', '本間知'),
  ('A', '049', '小川正孝'),
  ('A', '050', '関口真公'),
  ('A', '051', '附田晃弘'),
  ('A', '052', '附田茂光'),
  ('A', '053', '-'),
  ('A', '054', '吉本寛之'),
  ('A', '055', '高村孝博'),
  ('A', '056', '田代精米所'),
  ('A', '057', '佐々木亙'),
  ('A', '058', '高村寛(返却)'),
  ('A', '059', '福島浩二'),
  ('A', '060', '浅原克哉'),
  ('A', '061', '一戸トヨ'),
  ('A', '062', '太田孝治'),
  ('A', '063', '力石健市'),
  ('A', '064', '佐々木建悦'),
  ('A', '065', '佐々木喜代治'),
  ('A', '066', '沼村政志'),
  ('A', '067', '山田誠治'),
  ('A', '068', 'ＴＦ'),
  ('A', '069', '織笠利美'),
  ('A', '071', '新谷利彦'),
  ('A', '072', '(有)高橋苗圃'),
  ('A', '073', '米田均'),
  ('A', '074', '佐々木敏夫'),
  ('A', '075', 'ジェットさん'),
  ('A', '076', '小林るりこ'),
  ('A', '077', '須田山'),
  ('A', '078', '石川幸雄'),
  ('A', '079', '石倉義則'),
  ('A', '080', '久野清隆'),
  ('A', '081', '佐々木正美'),
  ('A', '082', '岩崎春雄'),
  ('A', '083', '本間剛'),
  ('A', '084', '附田大昌'),
  ('A', '085', '蹴揚克幸'),
  ('A', '086', '楢崎潔'),
  ('A', '087', '滝沢美子'),
  ('A', '088', '林崎信也'),
  ('A', '089', '若松光雄'),
  ('A', '090', '北山青果'),
  ('A', '091', '櫛桁啓司'),
  ('A', '092', '竹林安信'),
  ('A', '093', '馬場美由杞'),
  ('A', '094', '新堂清悦'),
  ('A', '095', '二羽実'),
  ('A', '096', '関口巌'),
  ('A', '097', '佐々木政美'),
  ('A', '098', '漆畑好正'),
  ('A', '099', '西山文夫'),
  ('A', '100', '佐藤琢真'),
  ('A', '101', '田代精米所'),
  ('A', '102', '蛯名佳央里'),
  ('A', '103', '椛沢拳也'),
  ('A', '104', '高橋清一'),
  ('A', '105', '久田貴子'),
  ('A', '106', '(株)松山ハーブ農園'),
  ('A', '107', '佐藤正人'),
  ('A', '108', '山村勝蔵'),
  ('A', '109', '宮古隆'),
  ('A', '110', '(株)Youファーム'),
  ('A', '111', '鎌本貴幸'),
  ('A', '112', '山本牧場'),
  ('A', '113', '(株)おいらせ大地'),
  ('A', '114', '(株)TOWADAファーム'),
  ('A', '115', '山村武弘'),
  ('A', '116', '中村亙'),
  ('A', '117', '古田和之'),
  ('A', '118', '(有)今藏'),
  ('A', '119', '橘政晴'),
  ('A', '120', '赤石義周'),
  ('A', '121', '田嶌太一'),
  ('A', '122', '立崎裕也'),
  ('A', '123', '浦田一博'),
  ('A', '124', '中田兼治'),
  ('A', '125', '上村一男'),
  ('A', '126', '(株)タカヒロ'),
  ('A', '127', '吉田久雄'),
  ('A', '128', '音道博'),
  ('A', '129', '金村駿佑'),
  ('A', '130', '長谷光彦'),
  ('A', '131', '高屋きね'),
  ('A', '132', '中野渡優樹'),
  ('A', '133', '佐々木行子'),
  ('A', '134', '中村勝弘'),
  ('A', '135', '木野幸助'),
  ('A', '136', '中野渡のぶこ'),
  ('A', '137', '久田恒志'),
  ('A', '138', '小川由利子'),
  ('A', '139', '坂本嘉人'),
  ('A', '140', '滝沢重広'),
  ('A', '141', '漆戸徹'),
  ('A', '142', '根岸充博'),
  ('A', '143', '山崎伸哉'),
  ('A', '144', '浅原克也（市川）'),
  ('A', '145', '浅原克也（佐々木）'),
  ('A', '146', '蒲野建設株式会社'),
  ('A', '147', '織笠兵一'),
  ('A', '148', '滝沢産業農業部'),
  ('A', '149', '中渡勝雄'),
  ('A', '150', '立崎亨一'),
  ('A', '151', '鈴木ファーム(株)'),
  ('A', '152', '田中信夫'),
  ('A', '153', '米田幸生'),
  ('A', '154', '山端淳'),
  ('A', '155', '下山みづえ'),
  ('A', '156', '水尻 忠司'),
  ('A', '157', '高村実俊'),
  ('A', '158', '佐々木武美'),
  ('A', '159', '(株)甲田ファー夢'),
  ('A', '160', '佐々木誠'),
  ('A', '161', '最上直樹'),
  ('A', '162', '坪次男'),
  ('A', '163', '(株)グリーンソウル'),
  ('A', '164', 'リヴェールユートピア'),
  ('A', '165', '小平真幸'),
  ('A', '166', '鈴木浩文'),
  ('A', '167', '中岫均'),
  ('A', '168', '織笠伸明'),
  ('A', '169', '小川純也'),
  ('A', '170', '角武志'),
  ('A', '171', '中村禮子'),
  ('A', '172', '坂本治彦'),
  ('A', '173', '佐々木正幸'),
  ('A', '174', '岡田博文'),
  ('A', '175', '相内智明'),
  ('A', '176', '赤坂聡'),
  ('A', '177', '髙屋アキ'),
  ('A', '178', '小笠原宏一'),
  ('A', '179', '沼山守'),
  ('A', '180', '向井由広'),
  ('A', '181', '高屋光男'),
  ('A', '182', '枋木正雄'),
  ('A', '183', '附田儀悦'),
  ('A', '184', '下村農園（同）'),
  ('A', '185', '音道隆志'),
  ('A', '186', '二羽みき'),
  ('A', '187', '小笠原良'),
  ('A', '188', '蛯名博昭'),
  ('A', '189', '中野實'),
  ('A', '190', '太田徹'),
  ('A', '191', '行利弘'),
  ('A', '192', '山端厳'),
  ('A', '193', '中野渡誠子'),
  ('A', '194', '斉藤重美'),
  ('A', '195', '寺沢洋子'),
  ('A', '196', '小山駿龍'),
  ('A', '197', '小林正治'),
  ('A', '198', '高橋鋼生'),
  ('A', '199', '南玲旺'),
  ('A', '200', '髙松美里'),
  ('A', '201', '高橋右京'),
  ('A', '202', '佐々木道子'),
  ('A', '203', '簗場道雄'),
  ('A', '204', '泉山光夫'),
  ('A', '205', '後村義隆'),
  ('A', '206', '市川繁'),
  ('A', '207', '松田善作'),
  ('A', '208', '大下内博美'),
  ('A', '209', '長谷川義央'),
  ('A', '210', '(株)まるかつ'),
  ('A', '211', '田嶋豊春'),
  ('A', '212', '高松ひろみ'),
  ('A', '213', '二ツ森勇次'),
  ('A', '214', '古川義志'),
  ('A', '215', '鶴ヶ崎慎一'),
  ('A', '216', '川村理次'),
  ('A', '217', '畑中直美'),
  ('A', '218', 'ナカムラホーム 中村良夫'),
  ('A', '219', '山村佳寛'),
  ('A', '220', '小泉英徳'),
  ('A', '221', '才神俊夫'),
  ('A', '222', '舛館和博'),
  ('A', '223', '小笠原輝'),
  ('A', '224', '高村定俊'),
  ('A', '225', '山崎和幸'),
  ('A', '226', '野崎義弘'),
  ('A', '227', '畠山園之'),
  ('A', '228', '砂渡伸一'),
  ('A', '229', '織笠秀明'),
  ('A', '230', '川上肇'),
  ('A', '231', '米内山渉'),
  ('A', '232', '小田満'),
  ('A', '233', '(株)マルカ農産'),
  ('A', '234', '中村司'),
  ('A', '235', '大成ファーム'),
  ('A', '236', '柴田俊男'),
  ('A', '237', '中岫嘉仁'),
  ('A', '238', '中渡宮子'),
  ('A', '239', '久野尚樹'),
  ('A', '240', '中村博光'),
  ('A', '241', '新谷健朗'),
  ('A', '242', '青森農産(株)'),
  ('A', '243', '高森秀明'),
  ('A', '244', '中野渡繁敏'),
  ('A', '245', '大久保大一'),
  ('A', '246', '田嶋大'),
  ('A', '247', '㈲今蔵'),
  ('A', '248', '野中耕進'),
  ('A', '249', '土嶺要'),
  ('A', '250', '野月政紀'),
  ('A', '251', '川岸睦'),
  ('A', '252', '村上奈穂子'),
  ('A', '253', '竹内幾雄'),
  ('A', '254', '古川義志'),
  ('A', '255', '関口久美'),
  ('A', '256', '甲田一博'),
  ('A', '257', '一戸学'),
  ('A', '258', '金見一雄'),
  ('A', '259', '仁和文雄'),
  ('A', '260', '田中覚'),
  ('A', '261', '熊野邦子'),
  ('A', '262', '山端哲也'),
  ('A', '263', '藤川靖'),
  ('A', '264', '佐々木稔'),
  ('A', '265', '山下清行'),
  ('A', '266', '三幸金属農業事業部'),
  ('A', '267', '立崎健一'),
  ('A', '268', '滝沢誠章'),
  ('A', '269', '芋田一弘'),
  ('A', '270', '甲田 繁美'),
  ('A', '271', '伊沢満二'),
  ('A', '272', '古川康治'),
  ('A', '273', '千葉彩加'),
  ('A', '274', '畠山一'),
  ('A', '275', '新山智哉'),
  ('A', '276', '立崎貢大'),
  ('A', '277', '沖沢福男'),
  ('A', '278', '佐々木俊明'),
  ('A', '279', '織笠一考'),
  ('D', '01', '十美商事'),
  ('D', '02', 'ヤマキアネックス'),
  ('D', '03', '吉田屋'),
  ('D', '04', '谷内商店'),
  ('D', '05', 'TF'),
  ('D', '06', '㈱むつ総合卸売市場'),
  ('D', '07', '高谷商事(株)'),
  ('D', '08', '(株)まるかつ');

alter table public.producers
  add constraint producers_pkey
  primary key (producer_source, producer_no);

create or replace view public.pallet_detail_view as
select
  d.pallet_no,
  d.detail_no,
  d.producer_no,
  coalesce(p.producer_name, '') as producer_name,
  d.standard,
  d.weight,
  d.price,
  d.memo
from public.pallet_details d
left join public.producers p on (
  case
    when length(regexp_replace(d.producer_no, '\D', '', 'g')) >= 7 then
      p.producer_source = 'D'
      and lpad(regexp_replace(p.producer_no, '\D', '', 'g'), 2, '0') = right(regexp_replace(d.producer_no, '\D', '', 'g'), 2)
    when length(regexp_replace(d.producer_no, '\D', '', 'g')) >= 4 then
      p.producer_source = 'A'
      and lpad(regexp_replace(p.producer_no, '\D', '', 'g'), 3, '0') = right(regexp_replace(d.producer_no, '\D', '', 'g'), 3)
    else
      p.producer_source = 'A'
      and lpad(regexp_replace(p.producer_no, '\D', '', 'g'), 3, '0') = lpad(regexp_replace(d.producer_no, '\D', '', 'g'), 3, '0')
  end
);

insert into public.app_settings (setting_key, setting_value, updated_at)
values (
  'producer_import_source',
  jsonb_build_object(
    'sourceName', 'Excel',
    'path', 'G:\マイドライブ\にんにく管理\令和8年\にんにく仕入れ管理表 エイト 令和8年産.xlsm',
    'sheetName', '仕入先一覧表',
    'lastSyncedAt', now()::text,
    'fileUpdatedAt', '2026-06-15T15:41:28+09:00',
    'aCount', 278,
    'dCount', 8
  ),
  now()
)
on conflict (setting_key) do update
  set setting_value = excluded.setting_value,
      updated_at = now();

create or replace function public.save_app_setting(p_worker_id text, p_setting_key text, p_setting_value jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_worker public.workers%rowtype;
  v_key text;
  v_value jsonb;
begin
  v_worker := public.require_active_worker(p_worker_id);
  v_key := btrim(coalesce(p_setting_key, ''));
  v_value := coalesce(p_setting_value, '{}'::jsonb);

  if v_key = '' then
    raise exception '設定キーが空です。';
  end if;

  insert into public.app_settings (setting_key, setting_value, updated_at)
  values (v_key, v_value, now())
  on conflict (setting_key) do update
    set setting_value = excluded.setting_value,
        updated_at = now();

  perform public.write_history(v_worker, 'マスタ設定', '', '', '', '設定を保存しました: ' || v_key, '');

  return jsonb_build_object('ok', true, 'message', '設定を保存しました。', 'settingKey', v_key);
end;
$$;

revoke all on function public.save_app_setting(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.save_app_setting(text, text, jsonb) to anon;

commit;

-- 件数メモ: A列 278 件 / D列 8 件 / 合計 286 件
