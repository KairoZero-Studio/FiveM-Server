COOKIE SAFEZONE V4.6.1

수정 사항
- cookie_zone 현재 DB 컬럼(center_x/center_y/center_z, size_length/size_width/size_height, beacon_r/g/b/a)에 맞게 뉴비 비콘 마이그레이션 쿼리 수정
- 구형 cx/cy/cz, length/width/height, color_r/g/b/a 조회/INSERT 제거
- Unknown column 'cx' in 'SELECT' 초기화 오류 수정
- 기존 존/팩션/차고/낚시/광산/잠수존 데이터는 삭제하지 않음
