

Locales["ko"] = {
    UI = {
        modal = {
            save = {
                title = "커마 저장",
                description = "이대로 저장됩니다"
            },
            exit = {
                title = "커마 나가기",
                description = "변경 사항이 저장되지 않습니다"
            },
            accept = "예",
            decline = "아니요"
        },
        ped = {
            title = "캐릭터 모델",
            model = "모델"
        },
        headBlend = {
            title = "유전(부모)",
            shape = {
                title = "얼굴형",
                firstOption = "아버지형",
                secondOption = "어머니형",
                mix = "혼합 비율"
            },
            skin = {
                title = "피부",
                firstOption = "아버지형",
                secondOption = "어머니형",
                mix = "혼합 비율"
            },
            race = {
                title = "인종",
                shape = "형태",
                skin = "피부",
                mix = "혼합 비율"
            }
        },
        faceFeatures = {
            title = "얼굴 형태",
            nose = {
                title = "코",
                width = "너비",
                height = "높이",
                size = "크기",
                boneHeight = "콧대 높이",
                boneTwist = "콧대 뒤틀림",
                peakHeight = "콧등 높이"
            },
            eyebrows = {
                title = "눈썹",
                height = "높이",
                depth = "깊이"
            },
            cheeks = {
                title = "볼",
                boneHeight = "광대 높이",
                boneWidth = "광대 너비",
                width = "너비"
            },
            eyesAndMouth = {
                title = "눈·입",
                eyesOpening = "눈 크기",
                lipsThickness = "입술 두께"
            },
            jaw = {
                title = "턱",
                width = "너비",
                size = "크기"
            },
            chin = {
                title = "턱끝",
                lowering = "낮춤",
                length = "길이",
                size = "크기",
                hole = "턱끝 홈"
            },
            neck = {
                title = "목",
                thickness = "두께"
            }
        },
        headOverlays = {
            title = "외형",
            hair = {
                title = "헤어",
                style = "스타일",
                color = "색상",
                highlight = "하이라이트",
                texture = "질감",
                fade = "페이드"
            },
            opacity = "투명도",
            style = "스타일",
            color = "색상",
            secondColor = "보조 색상",
            blemishes = "잡티",
            beard = "수염",
            eyebrows = "눈썹",
            ageing = "노화",
            makeUp = "메이크업",
            blush = "블러셔",
            complexion = "혈색",
            sunDamage = "햇빛 손상",
            lipstick = "립스틱",
            moleAndFreckles = "점·주근깨",
            chestHair = "가슴 털",
            bodyBlemishes = "몸 잡티",
            eyeColor = "눈동자 색"
        },
        components = {
            title = "의상",
            drawable = "종류",
            texture = "텍스처",
            mask = "마스크",
            upperBody = "손·팔",
            lowerBody = "하의",
            bags = "가방·낙하산",
            shoes = "신발",
            scarfAndChains = "스카프·목걸이",
            shirt = "상의",
            bodyArmor = "방탄복",
            decals = "데칼",
            jackets = "재킷",
            head = "머리"
        },
        props = {
            title = "장신구",
            drawable = "종류",
            texture = "텍스처",
            hats = "모자·헬멧",
            glasses = "안경",
            ear = "귀걸이",
            watches = "시계",
            bracelets = "팔찌"
        },
        tattoos = {
            title = "문신",
            items = {
                ZONE_TORSO = "몸통",
                ZONE_HEAD = "머리",
                ZONE_LEFT_ARM = "왼팔",
                ZONE_RIGHT_ARM = "오른팔",
                ZONE_LEFT_LEG = "왼다리",
                ZONE_RIGHT_LEG = "오른다리"
            },
            apply = "적용",
            delete = "제거",
            deleteAll = "문신 전체 제거",
            opacity = "투명도"
        }
    },
    outfitManagement = {
        title = "복장 관리",
        jobText = "직업 복장 관리",
        gangText = "갱 복장 관리"
    },
    cancelled = {
        title = "커마 취소",
        description = "커마가 저장되지 않았습니다"
    },
    outfits = {
        import = {
            title = "복장 코드 입력",
            menuTitle = "복장 불러오기",
            description = "공유 코드로 복장을 불러옵니다",
            name = {
                label = "복장 이름 지정",
                placeholder = "멋진 복장",
                default = "불러온 복장"
            },
            code = {
                label = "복장 코드"
            },
            success = {
                title = "복장 불러오기 완료",
                description = "이제 복장 메뉴에서 해당 복장으로 갈아입을 수 있습니다"
            },
            failure = {
                title = "불러오기 실패",
                description = "잘못된 복장 코드입니다"
            }
        },
        generate = {
            title = "복장 코드 생성",
            description = "공유용 복장 코드를 생성합니다",
            failure = {
                title = "문제가 발생했습니다",
                description = "복장 코드 생성에 실패했습니다"
            },
            success = {
                title = "복장 코드 생성 완료",
                description = "복장 코드는 다음과 같습니다"
            }
        },
        save = {
            menuTitle = "현재 복장 저장",
            menuDescription = "현재 복장을 %s 복장으로 저장합니다",
            description = "현재 복장을 저장합니다",
            title = "복장 이름 지정",
            managementTitle = "관리 복장 정보",
            name = {
                label = "복장 이름",
                placeholder = "아주 멋진 복장"
            },
            gender = {
                label = "성별",
                male = "남성",
                female = "여성"
            },
            rank = {
                label = "최소 등급"
            },
            failure = {
                title = "저장 실패",
                description = "같은 이름의 복장이 이미 있습니다"
            },
            success = {
                title = "성공",
                description = "복장 %s이(가) 저장되었습니다"
            }
        },
        update = {
            title = "복장 갱신",
            description = "현재 의상을 기존 복장에 덮어 저장합니다",
            failure = {
                title = "갱신 실패",
                description = "해당 복장이 존재하지 않습니다"
            },
            success = {
                title = "성공",
                description = "복장 %s이(가) 갱신되었습니다"
            }
        },
        change = {
            title = "복장 변경",
            description = "저장된 %s 복장 중에서 선택하세요",
            pDescription = "저장된 복장 중에서 선택하세요",
            failure = {
                title = "문제가 발생했습니다",
                description = "변경하려는 복장에 기본 외형이 없습니다",
            }
        },
        delete = {
            title = "복장 삭제",
            description = "저장된 %s 복장을 삭제합니다",
            mDescription = "저장된 복장을 삭제합니다",
            item = {
                title = '"%s" 삭제',
                description = "모델: %s%s"
            },
            success = {
                title = "성공",
                description = "복장이 삭제되었습니다"
            }
        },
        manage = {
            title = "👔 | %s 복장 관리"
        }
    },
    jobOutfits = {
        title = "근무 복장",
        description = "근무 복장 중에서 선택하세요"
    },
    menu = {
        returnTitle = "돌아가기",
        title = "탈의실",
        outfitsTitle = "내 복장",
        clothingShopTitle = "옷 가게",
        barberShopTitle = "미용실",
        tattooShopTitle = "문신 가게",
        surgeonShopTitle = "성형외과"
    },
    clothing = {
        title = "의상 구매 - $%d",
        titleNoPrice = "의상 변경",
        options = {
            title = "👔 | 옷 가게 옵션",
            description = "다양한 아이템 중에서 골라 입으세요"
        },
        outfits = {
            title = "👔 | 복장 옵션",
            civilian = {
                title = "시민 복장",
                description = "옷을 입습니다"
            }
        }
    },
    commands = {
        reloadskin = {
            title = "캐릭터 외형을 새로고침합니다",
            failure = {
                title = "오류",
                description = "지금은 reloadskin을 사용할 수 없습니다"
            }
        },
        clearstuckprops = {
            title = "엔티티에 붙은 모든 장신구를 제거합니다",
            failure = {
                title = "오류",
                description = "지금은 clearstuckprops를 사용할 수 없습니다"
            }
        },
        pedmenu = {
            title = "의상 메뉴 열기/부여",
            failure = {
                title = "오류",
                description = "플레이어가 접속 중이 아닙니다"
            }
        },
        joboutfits = {
            title = "직업 복장 메뉴를 엽니다"
        },
        gangoutfits = {
            title = "갱 복장 메뉴를 엽니다"
        },
        bossmanagedoutfits = {
            title = "보스 관리 복장 메뉴를 엽니다"
        }
    },
    textUI = {
        clothing = "옷 가게 - 가격: $%d",
        barber = "미용실 - 가격: $%d",
        tattoo = "문신 가게 - 가격: $%d",
        surgeon = "성형외과 - 가격: $%d",
        clothingRoom = "탈의실",
        playerOutfitRoom = "복장"
    },
    migrate = {
        success = {
            title = "성공",
            description = "이전 완료. 스킨 %s개 이전됨",
            descriptionSingle = "스킨 이전됨"
        },
        skip = {
            title = "안내",
            description = "스킨 건너뜀"
        },
        typeError = {
            title = "오류",
            description = "잘못된 유형"
        }
    },
    purchase = {
        tattoo = {
            success = {
                title = "성공",
                description = "%s 문신을 %s$에 구매했습니다"
            },
            failure = {
                title = "문신 적용 실패",
                description = "돈이 부족합니다!"
            }
        },
        store = {
            success = {
                title = "성공",
                description = "$%s를 %s에게 지급했습니다!"
            },
            failure = {
                title = "어뷰징!",
                description = "돈이 부족합니다! 시스템 악용 시도가 감지되었습니다!"
            }
        }
    }
}
