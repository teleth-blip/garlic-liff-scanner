const CONFIG = {
  supabaseUrl: 'https://yedrlbrzrkbtgswzplia.supabase.co',
  settingKey: 'producer_import_source',
  defaultExcelSource: 'https://drive.google.com/file/d/1ldXwvEHjKce0py91zJA4_T_AOSvrsWKg/view?usp=drive_link',
  defaultSheetName: '仕入先一覧表',
  triggerHandler: 'scheduledProducerSync',
  propertyServiceKey: 'SUPABASE_SERVICE_ROLE_KEY',
  propertyUrlKey: 'SUPABASE_URL'
};

function doGet(e) {
  return handleRequest_(e);
}

function doPost(e) {
  return handleRequest_(e);
}

function handleRequest_(e) {
  const action = String((e && e.parameter && e.parameter.action) || 'sync');
  try {
    if (action === 'setup') {
      installHourlyProducerSyncTrigger();
      return json_({ ok: true, message: '生産者マスタ同期トリガーを設定しました。' });
    }
    if (action === 'sync') {
      const result = syncProducerMaster_({
        forceCheck: String((e && e.parameter && e.parameter.force) || '') === '1',
        source: 'web'
      });
      return json_(Object.assign({ ok: true }, result));
    }
    return json_({ ok: false, error: '未対応の処理です: ' + action });
  } catch (error) {
    console.error(error);
    return json_({ ok: false, error: error.message || String(error) });
  }
}

function scheduledProducerSync() {
  return syncProducerMaster_({ forceCheck: false, source: 'trigger' });
}

function installHourlyProducerSyncTrigger() {
  ScriptApp.getProjectTriggers().forEach(trigger => {
    if (trigger.getHandlerFunction() === CONFIG.triggerHandler) {
      ScriptApp.deleteTrigger(trigger);
    }
  });
  ScriptApp.newTrigger(CONFIG.triggerHandler).timeBased().everyHours(1).create();
}

function syncProducerMaster_(options) {
  const now = new Date();
  const setting = getProducerSetting_();
  const intervalHours = Math.max(1, Math.floor(Number(setting.syncIntervalHours || 1)));
  if (!options.forceCheck && setting.lastCheckedAt) {
    const nextCheckAt = new Date(new Date(setting.lastCheckedAt).getTime() + intervalHours * 60 * 60 * 1000);
    if (now < nextCheckAt) {
      return {
        skipped: true,
        reason: 'interval',
        message: '更新間隔内のため確認をスキップしました。',
        nextCheckAt: nextCheckAt.toISOString()
      };
    }
  }

  const sourceText = setting.path || setting.fileId || CONFIG.defaultExcelSource;
  const sheetName = setting.sheetName || CONFIG.defaultSheetName;
  const file = resolveDriveFile_(sourceText);
  const fileId = file.getId();
  const fileUpdatedAt = file.getLastUpdated();
  const fileUpdatedIso = fileUpdatedAt.toISOString();

  if (!options.forceCheck && setting.fileUpdatedAt && new Date(setting.fileUpdatedAt).getTime() >= fileUpdatedAt.getTime()) {
    updateProducerSetting_(Object.assign({}, setting, {
      path: sourceText,
      fileId: fileId,
      sheetName: sheetName,
      syncIntervalHours: intervalHours,
      lastCheckedAt: now.toISOString(),
      fileUpdatedAt: fileUpdatedIso,
      lastResult: 'skipped_no_update'
    }));
    return {
      skipped: true,
      reason: 'not_modified',
      message: 'Excelファイルは前回同期時から更新されていません。',
      fileUpdatedAt: fileUpdatedIso
    };
  }

  let convertedFileId = '';
  try {
    convertedFileId = convertExcelToSpreadsheet_(fileId);
    const spreadsheet = SpreadsheetApp.openById(convertedFileId);
    const sheet = spreadsheet.getSheetByName(sheetName);
    if (!sheet) throw new Error('指定されたシートが見つかりません: ' + sheetName);

    const rows = readProducerRows_(sheet, fileUpdatedIso);
    replaceProducers_(rows);
    const aCount = rows.filter(row => row.producer_source === 'A').length;
    const dCount = rows.filter(row => row.producer_source === 'D').length;
    const aMaxNo = maxProducerNo_(rows, 'A');
    const dMaxNo = maxProducerNo_(rows, 'D');

    updateProducerSetting_(Object.assign({}, setting, {
      sourceName: 'Excel',
      path: sourceText,
      fileId: fileId,
      sheetName: sheetName,
      syncIntervalHours: intervalHours,
      lastCheckedAt: now.toISOString(),
      lastSyncedAt: now.toISOString(),
      fileUpdatedAt: fileUpdatedIso,
      aCount: aCount,
      dCount: dCount,
      aMaxNo: aMaxNo,
      dMaxNo: dMaxNo,
      lastResult: 'synced'
    }));

    return {
      skipped: false,
      message: '生産者マスタを同期しました。',
      sheetName: sheetName,
      fileUpdatedAt: fileUpdatedIso,
      aCount: aCount,
      dCount: dCount,
      aMaxNo: aMaxNo,
      dMaxNo: dMaxNo
    };
  } finally {
    if (convertedFileId) {
      DriveApp.getFileById(convertedFileId).setTrashed(true);
    }
  }
}

function readProducerRows_(sheet, fileUpdatedIso) {
  const values = sheet.getDataRange().getDisplayValues();
  const rowsByKey = {};
  values.forEach(row => {
    addProducerRow_(rowsByKey, 'A', row[0], row[1], 3, 999, fileUpdatedIso);
    addProducerRow_(rowsByKey, 'D', row[3], row[4], 2, 99, fileUpdatedIso);
  });
  return Object.keys(rowsByKey).sort().map(key => rowsByKey[key]);
}

function addProducerRow_(rowsByKey, source, rawNo, rawName, width, max, fileUpdatedIso) {
  const digits = String(rawNo || '').replace(/\D/g, '');
  if (!digits) return;
  const number = Number(digits);
  if (!number || number < 1 || number > max) return;
  const producerNo = String(number).padStart(width, '0');
  const producerName = String(rawName || '').trim();
  if (!producerName) return;
  rowsByKey[source + ':' + producerNo] = {
    producer_source: source,
    producer_no: producerNo,
    producer_name: producerName,
    source_updated_at: fileUpdatedIso
  };
}

function convertExcelToSpreadsheet_(fileId) {
  const file = DriveApp.getFileById(fileId);
  const resource = {
    name: 'producer-sync-' + Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyyMMdd-HHmmss'),
    mimeType: MimeType.GOOGLE_SHEETS
  };
  const created = Drive.Files.create(resource, file.getBlob(), { fields: 'id' });
  return created.id;
}

function resolveDriveFile_(sourceText) {
  const source = String(sourceText || '').trim();
  const fileId = extractDriveFileId_(source);
  if (fileId) return DriveApp.getFileById(fileId);

  const fileName = source.split(/[\\/]/).pop();
  if (!fileName) throw new Error('ExcelファイルIDまたはURLを設定してください。');
  const files = DriveApp.getFilesByName(fileName);
  if (!files.hasNext()) throw new Error('Google Drive上でExcelファイルが見つかりません: ' + fileName);
  return files.next();
}

function extractDriveFileId_(text) {
  const source = String(text || '').trim();
  let match = source.match(/\/d\/([a-zA-Z0-9_-]{20,})/);
  if (match) return match[1];
  match = source.match(/[?&]id=([a-zA-Z0-9_-]{20,})/);
  if (match) return match[1];
  if (/^[a-zA-Z0-9_-]{20,}$/.test(source)) return source;
  return '';
}

function getProducerSetting_() {
  const rows = supabaseRequest_('/rest/v1/app_settings?setting_key=eq.' + encodeURIComponent(CONFIG.settingKey) + '&select=setting_value', {
    method: 'get'
  });
  const setting = rows && rows[0] && rows[0].setting_value ? rows[0].setting_value : {};
  return Object.assign({
    sourceName: 'Excel',
    path: CONFIG.defaultExcelSource,
    sheetName: CONFIG.defaultSheetName,
    syncIntervalHours: 1,
    syncWebAppUrl: '',
    lastCheckedAt: '',
    lastSyncedAt: '',
    fileUpdatedAt: '',
    aCount: 0,
    dCount: 0,
    aMaxNo: 0,
    dMaxNo: 0
  }, setting || {});
}

function updateProducerSetting_(setting) {
  return supabaseRequest_('/rest/v1/app_settings?on_conflict=setting_key', {
    method: 'post',
    payload: JSON.stringify([{
      setting_key: CONFIG.settingKey,
      setting_value: setting
    }]),
    headers: {
      Prefer: 'resolution=merge-duplicates,return=minimal'
    }
  });
}

function upsertProducers_(rows) {
  const chunkSize = 500;
  for (let i = 0; i < rows.length; i += chunkSize) {
    const chunk = rows.slice(i, i + chunkSize);
    supabaseRequest_('/rest/v1/producers?on_conflict=producer_source,producer_no', {
      method: 'post',
      payload: JSON.stringify(chunk),
      headers: {
        Prefer: 'resolution=merge-duplicates,return=minimal'
      }
    });
  }
}

function replaceProducers_(rows) {
  if (!rows.length) throw new Error('Excelから生産者データを読み取れませんでした。シート名とA/B/D/E列を確認してください。');
  deleteProducersBySource_('A');
  deleteProducersBySource_('D');
  upsertProducers_(rows);
}

function deleteProducersBySource_(source) {
  supabaseRequest_('/rest/v1/producers?producer_source=eq.' + encodeURIComponent(source), {
    method: 'delete',
    headers: {
      Prefer: 'return=minimal'
    }
  });
}

function maxProducerNo_(rows, source) {
  return rows
    .filter(row => row.producer_source === source)
    .reduce((max, row) => Math.max(max, Number(row.producer_no || 0)), 0);
}

function supabaseRequest_(path, options) {
  const scriptProperties = PropertiesService.getScriptProperties();
  const baseUrl = (scriptProperties.getProperty(CONFIG.propertyUrlKey) || CONFIG.supabaseUrl).replace(/\/$/, '');
  const serviceKey = scriptProperties.getProperty(CONFIG.propertyServiceKey);
  if (!serviceKey) throw new Error('Script Properties に ' + CONFIG.propertyServiceKey + ' を設定してください。');

  const response = UrlFetchApp.fetch(baseUrl + path, {
    method: options.method || 'get',
    contentType: 'application/json',
    payload: options.payload,
    muteHttpExceptions: true,
    headers: Object.assign(getSupabaseAuthHeaders_(serviceKey), options.headers || {})
  });
  const status = response.getResponseCode();
  const text = response.getContentText();
  if (status < 200 || status >= 300) {
    throw new Error('Supabase APIエラー ' + status + ': ' + text);
  }
  return text ? JSON.parse(text) : null;
}

function getSupabaseAuthHeaders_(serviceKey) {
  const key = String(serviceKey || '').trim();
  validateSupabaseServiceKey_(key);
  const headers = { apikey: key };
  if (!key.startsWith('sb_secret_')) {
    headers.Authorization = 'Bearer ' + key;
  }
  return headers;
}

function validateSupabaseServiceKey_(key) {
  if (!key) throw new Error('Script Properties に ' + CONFIG.propertyServiceKey + ' を設定してください。');
  if (key.startsWith('sb_publishable_')) {
    throw new Error(CONFIG.propertyServiceKey + ' には公開用 publishable key ではなく、Secret key（sb_secret_...）または legacy service_role key を設定してください。');
  }

  const role = supabaseJwtRole_(key);
  if (role && role !== 'service_role') {
    throw new Error(CONFIG.propertyServiceKey + ' に service_role ではないJWTキーが設定されています。現在のrole: ' + role);
  }
}

function supabaseJwtRole_(key) {
  const parts = String(key || '').split('.');
  if (parts.length < 2) return '';
  try {
    const payload = Utilities.newBlob(Utilities.base64DecodeWebSafe(parts[1])).getDataAsString('UTF-8');
    return JSON.parse(payload).role || '';
  } catch (error) {
    return '';
  }
}

function json_(payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}
