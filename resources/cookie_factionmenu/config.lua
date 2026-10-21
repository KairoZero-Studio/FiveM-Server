Config = {}

Config.AllowedFactionTypes = {
    police = true,
    security = true,
    corrections = true,
    fire = true,
    ambulance = true,
    medical = true,
    mechanic = true,
    taxi = true,
    private = true,
    tow = true,
    crime = true,
}

Config.RequireDutyForGovernmentActions = true

-- 약국은 별도 faction type을 만들지 않습니다.
-- 팩션 이름에 아래 키워드가 포함되면 약국 전용 F5를 사용합니다.
-- 필요하면 팩션 ID를 직접 추가해 이름과 무관하게 약국 F5를 적용할 수 있습니다.
Config.PharmacyFactionNameKeywords = { '약국' }
Config.PharmacyFactionIds = {}

function Config.IsPharmacyFaction(faction)
    if type(faction) ~= 'table' then return false end
    local fid = tonumber(faction.id)
    if fid then
        for _, id in ipairs(Config.PharmacyFactionIds or {}) do
            if tonumber(id) == fid then return true end
        end
    end
    local name = tostring(faction.name or '')
    for _, keyword in ipairs(Config.PharmacyFactionNameKeywords or {}) do
        keyword = tostring(keyword or '')
        if keyword ~= '' and name:find(keyword, 1, true) then return true end
    end
    return false
end

-- 다이소도 별도 faction type 없이 팩션 이름으로 전용 F5를 사용합니다.
Config.DaisoFactionNameKeywords = { '다이소' }
Config.DaisoFactionIds = {}

function Config.IsDaisoFaction(faction)
    if type(faction) ~= 'table' then return false end
    local fid = tonumber(faction.id)
    if fid then
        for _, id in ipairs(Config.DaisoFactionIds or {}) do
            if tonumber(id) == fid then return true end
        end
    end
    local name = tostring(faction.name or '')
    for _, keyword in ipairs(Config.DaisoFactionNameKeywords or {}) do
        keyword = tostring(keyword or '')
        if keyword ~= '' and name:find(keyword, 1, true) then return true end
    end
    return false
end

Config.PharmacyCategories = {
    {
        id = 'pharmacy_sales', label = '약국 정산', subtitle = '판매가 · 공계 계산',
        actions = {
            { id='ci_pharmacy_calc', label='판매 · 정산 계산기', desc='매입가와 마진을 기준으로 판매가와 공동계좌 적립액을 계산합니다. 실제 입금은 자동으로 처리되지 않습니다.', icon='CALC', tone='green', mode='form', fields={
                {key='itemName', label='상품명', type='text', placeholder='예: 진통제', required=true},
                {key='buyPrice', label='개당 매입 단가', type='number', min=0, max=100000000, placeholder='원', required=true},
                {key='quantity', label='판매 수량', type='number', min=1, max=10000, default=1, required=true},
                {key='marginRate', label='목표 마진율 (%)', type='number', min=0, max=1000, default=30, required=true},
                {key='sellPrice', label='개당 판매가 직접 입력', type='number', min=0, max=100000000, default=0, placeholder='0이면 목표 마진율로 계산'},
                {key='shareRate', label='공동계좌 적립률 (%)', type='number', min=0, max=100, default=50, required=true},
            }},
        }
    },
    {
        id = 'pharmacy_account', label = '공동계좌', subtitle = '잔액 · 입금 · 출금',
        actions = {
            { id='ci_pharmacy_account', label='공동계좌 현황', desc='현재 공동계좌 잔액과 최근 수동 입출금 내역을 확인합니다.', icon='₩', tone='gold', mode='list' },
            { id='ci_pharmacy_deposit', label='공동계좌 입금', desc='내 은행 계좌에서 약국 공동계좌로 직접 입금합니다.', icon='+₩', tone='green', mode='form', fields={
                {key='amount', label='입금액', type='number', min=1, max=1000000000, required=true},
                {key='reason', label='입금 메모', type='text', placeholder='예: 진통제 판매 정산', required=true},
            }},
            { id='ci_pharmacy_withdraw', label='공동계좌 출금', desc='약국 공동계좌에서 내 은행 계좌로 출금합니다. 간부/대표만 사용할 수 있습니다.', icon='-₩', tone='red', mode='form', officerOnly=true, fields={
                {key='amount', label='출금액', type='number', min=1, max=1000000000, required=true},
                {key='reason', label='출금 사유', type='text', placeholder='예: 약품 매입비', required=true},
            }},
        }
    },
}


Config.DaisoCategories = {
    {
        id = 'daiso_sales', label = '다이소 판매', subtitle = '파츠 · 판매가 · 공계 계산',
        actions = {
            { id='ci_daiso_parts', label='판매 파츠 안내', desc='다이소에서 취급하는 총기 파츠 5종과 아이템 코드를 확인합니다.', icon='PART', tone='blue', mode='list' },
            { id='ci_catalog', label='판매 품목 및 가격', desc='팩션 관리에서 설정한 현재 판매 목록과 가격을 확인합니다.', icon='SHOP', tone='green', mode='list' },
            { id='ci_daiso_calc', label='판매 · 정산 계산기', desc='매입가와 마진을 기준으로 판매가와 공동계좌 적립액을 계산합니다. 실제 입금은 자동 처리하지 않습니다.', icon='CALC', tone='green', mode='form', fields={
                {key='itemName', label='상품명', type='text', placeholder='예: 소음기', required=true},
                {key='buyPrice', label='개당 매입 단가', type='number', min=0, max=100000000, placeholder='원', required=true},
                {key='quantity', label='판매 수량', type='number', min=1, max=10000, default=1, required=true},
                {key='marginRate', label='목표 마진율 (%)', type='number', min=0, max=1000, default=30, required=true},
                {key='sellPrice', label='개당 판매가 직접 입력', type='number', min=0, max=100000000, default=0, placeholder='0이면 목표 마진율로 계산'},
                {key='shareRate', label='공동계좌 적립률 (%)', type='number', min=0, max=100, default=50, required=true},
            }},
        }
    },
    {
        id = 'daiso_account', label = '공동계좌', subtitle = '잔액 · 입금 · 출금',
        actions = {
            { id='ci_daiso_account', label='공동계좌 현황', desc='현재 공동계좌 잔액과 최근 수동 입출금 내역을 확인합니다.', icon='₩', tone='gold', mode='list' },
            { id='ci_daiso_deposit', label='공동계좌 입금', desc='내 은행 계좌에서 다이소 공동계좌로 직접 입금합니다.', icon='+₩', tone='green', mode='form', fields={
                {key='amount', label='입금액', type='number', min=1, max=1000000000, required=true},
                {key='reason', label='입금 메모', type='text', placeholder='예: 소음기 판매 정산', required=true},
            }},
            { id='ci_daiso_withdraw', label='공동계좌 출금', desc='다이소 공동계좌에서 내 은행 계좌로 출금합니다. 간부/대표 권한이 필요합니다.', icon='-₩', tone='red', mode='form', officerOnly=true, fields={
                {key='amount', label='출금액', type='number', min=1, max=1000000000, required=true},
                {key='reason', label='출금 사유', type='text', placeholder='예: 파츠 매입비', required=true},
            }},
        }
    },
}


Config.CrimeCategories = {
    {
        id='crime_trade', label='조직 거래', subtitle='원재료 · 판매 · 환전',
        actions={
            {id='ci_crime_goods',label='조직 취급 품목',desc='원재료 4종과 완제품 4종의 아이템 코드 및 내 보유량을 확인합니다.',icon='BOX',tone='red',mode='list'},
            {id='ci_catalog',label='NPC 판매 품목 · 가격',desc='F3에서 설정된 현재 조직 NPC 판매목록과 가격을 확인합니다.',icon='SHOP',tone='gold',mode='list'},
            {id='ci_crime_trade_calc',label='거래 · 판매 계산기',desc='매입가/판매가/마진/공계 적립액을 계산합니다. 자동 정산은 하지 않습니다.',icon='CALC',tone='green',mode='form',fields={
                {key='itemName',label='거래 품목',type='text',placeholder='예: 코카인 원재료',required=true},
                {key='buyPrice',label='개당 매입가',type='number',min=0,max=100000000,required=true},
                {key='quantity',label='수량',type='number',min=1,max=10000,default=1,required=true},
                {key='marginRate',label='목표 마진율 (%)',type='number',min=0,max=1000,default=30,required=true},
                {key='sellPrice',label='개당 판매가 직접 입력',type='number',min=0,max=100000000,default=0,placeholder='0이면 마진율로 계산'},
                {key='shareRate',label='공동계좌 적립률 (%)',type='number',min=0,max=100,default=50,required=true},
            }},
            {id='ci_crime_exchange_calc',label='환전 계산기',desc='검은돈 금액과 환전율로 지급액/수수료를 계산합니다. 실제 돈은 자동 이동하지 않습니다.',icon='EX',tone='violet',mode='form',fields={
                {key='dirtyAmount',label='환전 요청 금액',type='number',min=1,max=1000000000,required=true},
                {key='exchangeRate',label='지급 비율 (%)',type='number',min=0,max=100,default=70,required=true},
                {key='accountRate',label='수수료 중 공계 적립률 (%)',type='number',min=0,max=100,default=50,required=true},
                {key='note',label='거래 메모',type='text',placeholder='선택 입력'},
            }},
            {id='ci_crime_robbery_tools',label='강도 RP 도구',desc='서버에 존재하는 대표 강도 RP 도구 코드와 내 보유량을 확인합니다.',icon='TOOL',tone='red',mode='list'},
        }
    },
    {
        id='crime_account',label='조직 공동계좌',subtitle='잔액 · 수동 입금 · 출금',
        actions={
            {id='ci_crime_account',label='공동계좌 현황',desc='조직 공동계좌와 최근 입출금 기록을 확인합니다.',icon='₩',tone='gold',mode='list'},
            {id='ci_crime_deposit',label='공동계좌 입금',desc='내 은행에서 조직 공동계좌로 직접 입금합니다.',icon='+₩',tone='green',mode='form',fields={
                {key='amount',label='입금액',type='number',min=1,max=1000000000,required=true},
                {key='reason',label='입금 메모',type='text',placeholder='거래 정산 / 환전 수수료 등',required=true},
            }},
            {id='ci_crime_withdraw',label='공동계좌 출금',desc='간부/대표 권한이 있는 직급만 출금할 수 있습니다.',icon='-₩',tone='red',mode='form',officerOnly=true,fields={
                {key='amount',label='출금액',type='number',min=1,max=1000000000,required=true},
                {key='reason',label='출금 사유',type='text',required=true},
            }},
        }
    },
    {
        id='crime_office',label='조직 업무망',subtitle='공지 · 내부 업무기록 · 휴가',
        actions={
            {id='ci_home',label='업무 대시보드',desc='조직 소속과 기본 업무 현황을 확인합니다.',icon='HOME',tone='blue',mode='list'},
            {id='ci_notice_list',label='조직 공지',desc='조직 내부 공지를 확인합니다.',icon='NEWS',tone='blue',mode='list'},
            {id='ci_notice_add',label='공지 등록',desc='간부 이상이 조직 공지를 등록합니다.',icon='+NEWS',tone='gold',mode='form',officerOnly=true,fields={
                {key='title',label='제목',type='text',required=true},{key='body',label='공지 내용',type='textarea',required=true}
            }},
            {id='ci_report_list',label='조직 업무 기록',desc='최근 내부 거래/활동 보고서를 확인합니다.',icon='DOC',tone='green',mode='list'},
            {id='ci_report_add',label='업무 기록 작성',desc='거래·환전·기타 조직 업무를 직접 기록합니다.',icon='+DOC',tone='green',mode='form',fields={
                {key='title',label='기록 제목',type='text',required=true},{key='body',label='상세 내용',type='textarea',required=true}
            }},
            {id='ci_leave_list',label='휴가 신청 현황',desc='본인의 신청 및 간부 승인 대기를 확인합니다.',icon='LOA',tone='violet',mode='list'},
            {id='ci_leave_apply',label='휴가 신청',desc='휴가 기간과 사유를 제출합니다.',icon='+LOA',tone='violet',mode='form',fields={
                {key='startDate',label='시작일 YYYY-MM-DD',type='text',required=true},{key='endDate',label='종료일 YYYY-MM-DD',type='text',required=true},{key='reason',label='사유',type='textarea',required=true}
            }},
        }
    },
}

Config.TypeLabels = {
    police = '경찰청',
    security = '보안국',
    corrections = '교정국',
    fire = '소방청',
    ambulance = '의료국',
    medical = '의료국',
    mechanic = '정비소',
    taxi = '택시회사',
    private = '사설팩션',
    tow = '렉카',
    crime = '조직',
    civil = '시민직',
}

-- 현장 단축키는 F5에서 제거.
-- NUM7/8/9, Y, G, PAGEUP, H, F1은 기존 키로만 사용한다.
Config.PoliceCategories = {
    {
        id = 'lookup', label = '조회', subtitle = '신원 · 차량 · 면허',
        actions = {
            { id='identity_lookup', label='신원 조회', desc='고번 또는 이름으로 시민 신원을 조회합니다.', icon='ID', tone='blue', mode='form', fields={
                {key='query', label='고번 / 이름', type='text', placeholder='예: 1 또는 도베르만', required=true}
            }},
            { id='vehicle_lookup', label='차량 조회', desc='번호판 또는 소유자 고번/이름으로 차량을 조회합니다.', icon='CAR', tone='blue', mode='form', fields={
                {key='query', label='번호판 / 소유자', type='text', placeholder='번호판 / 고번 / 이름', required=true}
            }},
            { id='license_lookup', label='면허 조회', desc='고번 또는 이름으로 보유 면허를 조회합니다.', icon='LIC', tone='violet', mode='form', fields={
                {key='query', label='고번 / 이름', type='text', placeholder='예: 1 또는 도베르만', required=true}
            }},
            { id='license_suspend', label='운전면허 정지', desc='경찰청/보안국이 죄목에 맞춰 분 단위로 운전면허를 정지합니다.', icon='LIC-', tone='red', mode='form', fields={
                {key='target', label='고번 / 이름', type='text', placeholder='예: 17 또는 김민수', required=true},
                {key='reason', label='죄목 / 정지 사유', type='textarea', placeholder='예: 난폭운전 / 음주운전', required=true},
                {key='minutes', label='면허 정지 시간(분)', type='number', min=1, max=60, placeholder='1~60분', required=true}
            }},
            { id='license_restore', label='운전면허 정지 해제', desc='잘못된 정지 또는 별도 사유가 있을 때 운전면허를 정상 복구합니다.', icon='LIC+', tone='green', mode='form', fields={
                {key='target', label='고번 / 이름', type='text', placeholder='예: 17 또는 김민수', required=true},
                {key='reason', label='정지 해제 사유', type='textarea', required=true}
            }},
            { id='roster', label='근무자 현황', desc='현재 소속 팩션의 계급과 출근 상태를 확인합니다.', icon='UNIT', tone='green', mode='list' },
        }
    },
    {
        id = 'wanted', label = '수배·영장', subtitle = '시간제 추격전 · 팩션 영장',
        actions = {
            { id='wanted_board', label='수배/도주 현황', desc='진행 중인 도주·수배를 확인하고 다른 경찰/보안국 인원이 추적에 참여할 수 있습니다.', icon='W', tone='red', mode='list' },
            { id='wanted_add', label='수배 등록', desc='고번/이름 대상에게 수배를 수동 등록합니다. 수배 시간은 30분으로 고정됩니다.', icon='W+', tone='red', mode='form', fields={
                {key='target', label='고번 / 이름', type='text', placeholder='예: 17 또는 김민수', required=true},
                {key='reason', label='수배 사유', type='textarea', placeholder='수배 사유를 입력하세요.', required=true}
            }},
            { id='escape_add', label='도주 등록', desc='현장에서 도주한 시민을 수동 등록합니다. 도주 시간은 20분으로 고정됩니다.', icon='E+', tone='red', mode='form', fields={
                {key='target', label='고번 / 이름', type='text', placeholder='예: 17 또는 김민수', required=true},
                {key='reason', label='도주 사유', type='textarea', placeholder='도주 상황을 기록하세요.', required=true}
            }},
            { id='appearance_board', label='출석 요구 현황', desc='경찰/보안국이 보낸 출석 요구의 응답·10분 대기·미출석 상태를 확인합니다.', icon='CALL', tone='blue', mode='list' },
            { id='appearance_add', label='출석 요구', desc='시민에게 사유가 포함된 출석 요구서를 보냅니다. 거절 시 즉시 수배가 등록됩니다.', icon='REQ', tone='blue', mode='form', fields={
                {key='target', label='고번 / 이름', type='text', placeholder='예: 17 또는 김민수', required=true},
                {key='reason', label='출석 요구 사유', type='textarea', placeholder='예: 살인, 뺑소니 관련 조사', required=true}
            }},
            { id='warrant_board', label='영장 현황', desc='팩션/조직을 대상으로 발부된 활성 영장을 확인하고 종료합니다.', icon='ORD', tone='gold', mode='list' },
            { id='warrant_add', label='팩션/조직 영장 등록', desc='간부 이상이 사설팩션·범죄조직 등을 대상으로 영장을 발부합니다.', icon='O+', tone='gold', mode='form', officerOnly=true, fields={
                {key='targetFactionId', label='대상 팩션 / 조직', type='factionselect', required=true},
                {key='warrantType', label='영장 종류', type='select', required=true, options={{value='search',label='수색 영장'},{value='raid',label='작전 영장'}}},
                {key='reason', label='발부 사유', type='textarea', required=true},
                {key='minutes', label='유효 시간(분)', type='number', placeholder='0 = 무기한', min=0, max=43200, default=0}
            }},
        }
    },
    {
        id = 'field', label = '현장업무', subtitle = '신고 · 벌금 · 수색 · 구금',
        actions = {
            { id='penalty_calculator', label='벌금·구금·면허 계산기', desc='공식 죄목을 선택하면 벌금·구금·면허정지·보석금이 자동 합산되어 한 번에 처리됩니다.', icon='CALC', tone='gold', mode='list' },
            { id='dispatch', label='신고/출동', desc='현재 활성 신고 및 지원요청을 확인하고 출동 참가합니다.', icon='CALL', tone='gold', mode='list' },
            { id='fine', label='벌금 부과', desc='가까운 시민을 고번/이름으로 지정해 벌금을 부과합니다.', icon='₩', tone='gold', mode='form', fields={
                {key='target', label='고번 / 이름', type='text', placeholder='예: 17 또는 김민수', required=true},
                {key='amount', label='벌금액', type='number', placeholder='원', min=1, max=50000000, required=true},
                {key='reason', label='위반 사유', type='textarea', required=true}
            }},
            { id='search_items', label='소지품 검사', desc='수갑이 채워진 가까운 시민을 고번/이름으로 지정해 소지품을 검사합니다.', icon='SRH', tone='blue', mode='form', fields={
                {key='target', label='고번 / 이름', type='text', placeholder='예: 17 또는 김민수', required=true}
            }},
            { id='seize_items', label='소지품 압수', desc='수갑이 채워진 대상의 물품을 압수합니다. 별도 증거 메뉴는 사용하지 않습니다.', icon='BOX', tone='red', mode='form', fields={
                {key='target', label='고번 / 이름', type='text', placeholder='예: 17 또는 김민수', required=true},
                {key='item', label='아이템 코드', type='text', placeholder='예: weapon_pistol', required=true},
                {key='count', label='수량', type='number', min=1, max=1000, required=true},
                {key='reason', label='압수 사유', type='text', required=true}
            }},
            { id='detain', label='구금 집행', desc='수갑이 채워진 시민을 고번/이름으로 지정해 구금합니다.', icon='JAIL', tone='red', mode='form', fields={
                {key='target', label='고번 / 이름', type='text', placeholder='예: 17 또는 김민수', required=true},
                {key='charge', label='죄목', type='text', required=true},
                {key='fine', label='벌금액', type='number', min=0, max=50000000},
                {key='minutes', label='구금 시간(분)', type='number', min=1, max=720, required=true},
                {key='note', label='메모', type='textarea'}
            }},
            { id='release', label='석방 처리', desc='현재 구금 중인 시민을 고번/이름으로 지정해 즉시 석방합니다.', icon='OUT', tone='green', mode='form', fields={
                {key='target', label='고번 / 이름', type='text', placeholder='예: 17 또는 김민수', required=true},
                {key='reason', label='석방 사유', type='text', placeholder='선택 입력'}
            }},
        }
    },
    {
        id = 'case', label = '사건·기록', subtitle = '사건보고 · 업무기록',
        actions = {
            { id='cases', label='사건 목록', desc='최근 사건과 처리 상태를 확인합니다.', icon='CASE', tone='blue', mode='list' },
            { id='case_report', label='사건 보고서', desc='사건 제목, 피의자 고번/이름, 경위와 처리 결과를 기록합니다.', icon='DOC', tone='blue', mode='form', fields={
                {key='title', label='사건명', type='text', required=true},
                {key='suspect', label='피의자 고번 / 이름', type='text', placeholder='선택 입력'},
                {key='summary', label='사건 경위', type='textarea', required=true},
                {key='result', label='처리 결과', type='textarea', placeholder='체포 / 경고 / 현장종결 등'}
            }},
            { id='audit', label='업무 로그', desc='최근 수배·영장·벌금·구금·사건 처리 기록을 확인합니다.', icon='LOG', tone='green', mode='list' },
        }
    },
    {
        id = 'intranet', label = '인트라넷', subtitle = '장부 · 실적 · 휴가 · 정산',
        actions = {
            { id='intranet_home', label='인트라넷 홈', desc='이번 주 근무·벌금·팩션 공금·휴가 대기 현황을 한눈에 봅니다.', icon='HOME', tone='blue', mode='list' },
            { id='intranet_ledger', label='장부', desc='경찰청/보안국 공금 변동과 최근 장부를 확인합니다.', icon='BOOK', tone='gold', mode='list' },
            { id='intranet_ledger_add', label='장부 입력', desc='간부가 수입/지출 내역을 공금과 함께 기록합니다.', icon='+BOOK', tone='gold', mode='form', officerOnly=true, fields={
                {key='kind',label='구분',type='select',required=true,options={{value='expense',label='지출'},{value='income',label='수입'}}},
                {key='amount',label='금액',type='number',min=1,max=1000000000,required=true},
                {key='reason',label='내용',type='text',required=true}
            }},
            { id='intranet_performance', label='실적', desc='이번 주 근무시간·벌금·구금·사건 실적을 팩션원별로 집계합니다.', icon='STAT', tone='green', mode='list' },
            { id='intranet_leave_board', label='휴가 현황', desc='팩션원의 휴가/휴직 신청과 승인 상태를 확인합니다.', icon='LOA', tone='violet', mode='list' },
            { id='intranet_leave_request', label='휴가 신청', desc='휴가 기간과 사유를 제출합니다.', icon='+LOA', tone='violet', mode='form', fields={
                {key='startDate',label='시작일',type='text',placeholder='YYYY-MM-DD',required=true},
                {key='endDate',label='종료일',type='text',placeholder='YYYY-MM-DD',required=true},
                {key='reason',label='사유',type='textarea',required=true}
            }},
            { id='intranet_settlement_board', label='정산 내역', desc='간부가 최근 정산 지급 내역을 확인합니다.', icon='PAY', tone='green', mode='list', officerOnly=true },
            { id='intranet_settlement_pay', label='정산 지급', desc='팩션 공금에서 소속 팩션원 은행으로 실제 정산금을 지급합니다.', icon='+PAY', tone='green', mode='form', officerOnly=true, fields={
                {key='target',label='대상 고번 / 이름',type='text',required=true},
                {key='amount',label='정산액',type='number',min=1,max=1000000000,required=true},
                {key='note',label='정산 내용',type='text',placeholder='주간 실적 정산 / 수당 등'}
            }},
        }
    },
    {
        id = 'finance', label = '재정', subtitle = '공금 · 벌금 수입',
        actions = {
            { id='budget_lookup', label='공금 조회', desc='간부 이상이 현재 팩션 공금과 최근 변동을 확인합니다.', icon='₩', tone='gold', mode='list', officerOnly=true },
            { id='budget_deposit', label='공금 입금', desc='개인 은행 계좌에서 팩션 공금으로 입금합니다.', icon='+₩', tone='green', mode='form', officerOnly=true, fields={
                {key='amount', label='입금액', type='number', min=1, max=100000000, required=true},
                {key='reason', label='입금 사유', type='text', placeholder='예: 운영비'}
            }},
        }
    },
}

Config.TowCategories = {
    {
        id = 'tow_field', label = '렉카 현장업무', subtitle = '압류 · 폐차 · 현황',
        actions = {
            { id='ci_tow_impounds', label='압류 차량 현황', desc='현재 렉카 팩션이 압류 중인 차량을 확인하고 간부가 압류를 해제합니다.', icon='CAR', tone='red', mode='list' },
            { id='ci_tow_scraps', label='폐차 처리 기록', desc='최근 폐차 처리 차량과 담당자, 합의 금액을 확인합니다.', icon='SCRAP', tone='gold', mode='list' },
            { id='ci_tow_fee_calc', label='렉카 요금 계산기', desc='견인비·보관료·추가 작업비를 합산합니다. 실제 결제/입금은 자동 처리하지 않습니다.', icon='CALC', tone='blue', mode='form', fields={
                {key='towFee',label='견인비',type='number',min=0,max=100000000,default=0},
                {key='storagePerDay',label='1일 보관료',type='number',min=0,max=100000000,default=0},
                {key='days',label='보관 일수',type='number',min=0,max=365,default=0},
                {key='extraFee',label='추가 작업비',type='number',min=0,max=100000000,default=0},
                {key='note',label='작업 메모',type='text',placeholder='선택 입력'}
            }},
        }
    },
    {
        id = 'tow_account', label = '공동계좌', subtitle = '잔액 · 수동 입금 · 출금',
        actions = {
            { id='ci_tow_account', label='공동계좌 현황', desc='렉카 공동계좌 잔액과 최근 수동 입출금 내역을 확인합니다.', icon='₩', tone='gold', mode='list' },
            { id='ci_tow_deposit', label='공동계좌 입금', desc='내 은행 계좌에서 렉카 공동계좌로 직접 입금합니다.', icon='+₩', tone='green', mode='form', fields={
                {key='amount',label='입금액',type='number',min=1,max=1000000000,required=true},
                {key='reason',label='입금 메모',type='text',placeholder='견인비 / 압류비 / 폐차 정산 등',required=true}
            }},
            { id='ci_tow_withdraw', label='공동계좌 출금', desc='간부/대표 권한이 있는 직급이 공동계좌에서 출금합니다.', icon='-₩', tone='red', mode='form', officerOnly=true, fields={
                {key='amount',label='출금액',type='number',min=1,max=1000000000,required=true},
                {key='reason',label='출금 사유',type='text',required=true}
            }},
        }
    },
    {
        id = 'tow_office', label = '렉카 업무망', subtitle = '공지 · 업무기록 · 휴가',
        actions = {
            {id='ci_home',label='업무 대시보드',desc='소속, 출근 상태, 미처리 업무를 확인합니다.',icon='HOME',tone='blue',mode='list'},
            {id='ci_notice_list',label='팩션 공지',desc='렉카 내부 공지를 확인합니다.',icon='NEWS',tone='blue',mode='list'},
            {id='ci_notice_add',label='공지 등록',desc='간부 이상이 공지를 등록합니다.',icon='+NEWS',tone='gold',mode='form',officerOnly=true,fields={
                {key='title',label='제목',type='text',required=true},{key='body',label='공지 내용',type='textarea',required=true}
            }},
            {id='ci_report_list',label='업무 보고서',desc='최근 견인·압류·폐차 업무 기록을 확인합니다.',icon='DOC',tone='green',mode='list'},
            {id='ci_report_add',label='업무 보고서 작성',desc='렉카 업무 내용을 직접 기록합니다.',icon='+DOC',tone='green',mode='form',fields={
                {key='title',label='보고 제목',type='text',required=true},{key='body',label='상세 내용',type='textarea',required=true}
            }},
            {id='ci_leave_list',label='휴가 신청 현황',desc='본인의 신청 내역과 간부용 승인 대기를 확인합니다.',icon='LOA',tone='violet',mode='list'},
            {id='ci_leave_apply',label='휴가 신청',desc='휴가 기간과 사유를 제출합니다.',icon='+LOA',tone='violet',mode='form',fields={
                {key='startDate',label='시작일 YYYY-MM-DD',type='text',required=true},{key='endDate',label='종료일 YYYY-MM-DD',type='text',required=true},{key='reason',label='사유',type='textarea',required=true}
            }},
        }
    },
}

-- Police / Security: preserve all existing police functions & intranet as-is.
-- Other factions: independent job-specific intranet; the server checks membership and rank again.
Config.GenericIntranetCategories = {
    { id='desk', label='업무망', subtitle='공지 · 근무 현황 · 휴가', actions={
        {id='ci_home',label='업무 대시보드',desc='소속, 출근 상태, 미처리 업무를 확인합니다.',icon='HOME',tone='blue',mode='list'},
        {id='ci_notice_list',label='팩션 공지',desc='소속 팩션의 공지사항을 확인합니다.',icon='NEWS',tone='blue',mode='list'},
        {id='ci_notice_add',label='공지 등록',desc='간부 이상이 팩션 공지를 등록합니다.',icon='+NEWS',tone='gold',mode='form',officerOnly=true,fields={
            {key='title',label='제목',type='text',required=true},
            {key='body',label='공지 내용',type='textarea',required=true}
        }},
        {id='ci_leave_list',label='휴가 신청 현황',desc='본인의 신청 내역과 간부용 승인 대기를 확인합니다.',icon='LOA',tone='violet',mode='list'},
        {id='ci_leave_apply',label='휴가 신청',desc='휴가 기간과 사유를 제출합니다.',icon='+LOA',tone='violet',mode='form',fields={
            {key='startDate',label='시작일 YYYY-MM-DD',type='text',required=true},
            {key='endDate',label='종료일 YYYY-MM-DD',type='text',required=true},
            {key='reason',label='사유',type='textarea',required=true}
        }},
    }},
    { id='report', label='업무 기록', subtitle='팩션별 전용 일지', actions={
        {id='ci_report_list',label='업무 보고서 목록',desc='해당 팩션의 최근 업무 기록을 확인합니다.',icon='DOC',tone='green',mode='list'},
        {id='ci_report_add',label='업무 보고서 작성',desc='보고서를 작성하고 내부에 저장합니다.',icon='+DOC',tone='green',mode='form',fields={
            {key='title',label='보고 제목',type='text',required=true},
            {key='body',label='상세 내용',type='textarea',required=true}
        }}
    }}
}

-- Only an informational price list: no purchase/money deduction/item transfer in V2.
local ciCatalog = { id='shop',label='판매 안내',subtitle='품목·가격',actions={
    {id='ci_catalog',label='판매 품목 및 가격',desc='팩션 관리자가 설정한 판매 목록을 확인합니다.',icon='SHOP',tone='green',mode='list'}
}}
table.insert(Config.GenericIntranetCategories,ciCatalog)
table.insert(Config.PoliceCategories,ciCatalog)
Config.GenericFactionFeatures = {
    corrections = {'수감자 관리 기록', '교도소 업무 보고'},
    fire = {'출동 일지', '현장 안전 점검'},
    ambulance = {'구급 출동 일지', '치료 업무 보고'},
    medical = {'진료 업무 기록', '구급 출동 일지'},
    mechanic = {'정비 작업 일지', '부품·수리 업무 보고'},
    taxi = {'운행 일지', '승객 민원 기록'},
    private = {'업무 일지', '계약 관리 기록'},
    tow = {'견인·압류 업무 기록', '폐차 업무 기록'},
    crime = {'조직 내부 업무 기록'},
}
