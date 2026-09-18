"""
英语试卷模板配置
定义中国初中英语常见题型和试卷结构
"""

# 支持的英语题型定义
ENGLISH_QUESTION_TYPES = {
    '单选题': {
        'code': 'multiple_choice',
        'name_cn': '单选题',
        'name_en': 'Multiple Choice',
        'description': '四选一的选择题，测试语法、词汇、情景对话等',
        'typical_score': 1.0,
        'has_options': True,
        'has_passage': False,
        'sub_types': ['语法', '词汇', '情景交际', '固定搭配']
    },
    '完形填空': {
        'code': 'cloze_test',
        'name_cn': '完形填空',
        'name_en': 'Cloze Test',
        'description': '在短文中选词填空，测试综合语言运用能力',
        'typical_score': 1.0,
        'has_options': True,
        'has_passage': True,
        'sub_types': ['记叙文', '说明文', '议论文']
    },
    '阅读理解': {
        'code': 'reading_comprehension',
        'name_cn': '阅读理解',
        'name_en': 'Reading Comprehension',
        'description': '阅读文章后回答问题',
        'typical_score': 2.0,
        'has_options': True,
        'has_passage': True,
        'sub_types': ['细节理解', '主旨大意', '推理判断', '词义猜测', '标题归纳']
    },
    '任务型阅读': {
        'code': 'task_based_reading',
        'name_cn': '任务型阅读',
        'name_en': 'Task-based Reading',
        'description': '根据文章完成表格、回答问题、信息匹配等',
        'typical_score': 2.0,
        'has_options': False,
        'has_passage': True,
        'sub_types': ['信息归纳', '表格填空', '信息匹配', '回答问题']
    },
    '选词填空': {
        'code': 'word_selection',
        'name_cn': '选词填空',
        'name_en': 'Word Selection',
        'description': '从给定词汇中选择合适的词填空',
        'typical_score': 1.0,
        'has_options': True,
        'has_passage': True,
        'sub_types': ['词汇运用', '语境理解']
    },
    '语法填空': {
        'code': 'grammar_filling',
        'name_cn': '语法填空',
        'name_en': 'Grammar Filling',
        'description': '根据语法规则填空，可能给出提示词',
        'typical_score': 1.5,
        'has_options': False,
        'has_passage': True,
        'sub_types': ['有提示词', '无提示词']
    },
    '单词拼写': {
        'code': 'spelling',
        'name_cn': '单词拼写',
        'name_en': 'Spelling',
        'description': '根据句意和首字母或音标写单词',
        'typical_score': 1.0,
        'has_options': False,
        'has_passage': False,
        'sub_types': ['首字母提示', '音标提示', '中文提示']
    },
    '句型转换': {
        'code': 'sentence_transformation',
        'name_cn': '句型转换',
        'name_en': 'Sentence Transformation',
        'description': '改写句子，保持意思不变',
        'typical_score': 2.0,
        'has_options': False,
        'has_passage': False,
        'sub_types': ['同义句', '否定句', '疑问句', '被动语态', '时态转换']
    },
    '翻译': {
        'code': 'translation',
        'name_cn': '翻译',
        'name_en': 'Translation',
        'description': '中英文互译',
        'typical_score': 2.0,
        'has_options': False,
        'has_passage': False,
        'sub_types': ['中译英', '英译中', '句子翻译', '短语翻译']
    },
    '书面表达': {
        'code': 'writing',
        'name_cn': '书面表达',
        'name_en': 'Writing',
        'description': '根据要求写作文',
        'typical_score': 15.0,
        'has_options': False,
        'has_passage': False,
        'sub_types': ['电子邮件', '日记', '通知', '演讲稿', '看图作文', '议论文']
    }
}

# 预设试卷模板
PRESET_TEMPLATES = [
    {
        'name': '初中英语期中考试卷',
        'description': '适用于初中英语期中考试，全面考查听说读写能力',
        'category': '初中英语',
        'total_score': 120.0,
        'paper_size': 'A3',
        'structure': {
            'header': {
                'title': '初中英语期中考试',
                'subtitle': '时间：120分钟  满分：120分',
                'instructions': '注意事项：\n1. 本试卷分为选择题和非选择题两部分。\n2. 答题前，请将姓名、班级、考号填写在答题卡上。\n3. 所有答案必须填写在答题卡上，在试卷上答题无效。'
            },
            'sections': [
                {
                    'title': '一、听力部分（共20分）',
                    'type': '单选题',
                    'count': 20,
                    'score_per_item': 1.0,
                    'total_score': 20.0,
                    'description': '听录音，选择正确答案',
                    'difficulty': {
                        '简单': 8,
                        '中等': 10,
                        '困难': 2
                    }
                },
                {
                    'title': '二、单项选择（共15分）',
                    'type': '单选题',
                    'sub_type': '语法',
                    'count': 15,
                    'score_per_item': 1.0,
                    'total_score': 15.0,
                    'description': '从A、B、C、D四个选项中选择最佳答案',
                    'difficulty': {
                        '简单': 5,
                        '中等': 8,
                        '困难': 2
                    }
                },
                {
                    'title': '三、完形填空（共10分）',
                    'type': '完形填空',
                    'count': 10,
                    'score_per_item': 1.0,
                    'total_score': 10.0,
                    'description': '阅读下面短文，从各题所给的选项中选出最佳答案',
                    'passages': 1,
                    'difficulty': {
                        '简单': 3,
                        '中等': 5,
                        '困难': 2
                    }
                },
                {
                    'title': '四、阅读理解（共30分）',
                    'type': '阅读理解',
                    'count': 15,
                    'score_per_item': 2.0,
                    'total_score': 30.0,
                    'description': '阅读下列短文，根据短文内容选择最佳答案',
                    'passages': 3,
                    'questions_per_passage': 5,
                    'difficulty': {
                        '简单': 6,
                        '中等': 7,
                        '困难': 2
                    }
                },
                {
                    'title': '五、任务型阅读（共10分）',
                    'type': '任务型阅读',
                    'sub_type': '表格填空',
                    'count': 5,
                    'score_per_item': 2.0,
                    'total_score': 10.0,
                    'description': '阅读短文，根据短文内容完成表格',
                    'passages': 1,
                    'difficulty': {
                        '简单': 2,
                        '中等': 2,
                        '困难': 1
                    }
                },
                {
                    'title': '六、词汇运用（共10分）',
                    'type': '选词填空',
                    'count': 10,
                    'score_per_item': 1.0,
                    'total_score': 10.0,
                    'description': '用方框中所给词的适当形式填空',
                    'word_bank_size': 12,
                    'difficulty': {
                        '简单': 4,
                        '中等': 5,
                        '困难': 1
                    }
                },
                {
                    'title': '七、语法填空（共10分）',
                    'type': '语法填空',
                    'count': 10,
                    'score_per_item': 1.0,
                    'total_score': 10.0,
                    'description': '阅读下面短文，在空白处填入适当的词或括号内单词的正确形式',
                    'passages': 1,
                    'difficulty': {
                        '简单': 4,
                        '中等': 4,
                        '困难': 2
                    }
                },
                {
                    'title': '八、书面表达（共15分）',
                    'type': '书面表达',
                    'count': 1,
                    'score_per_item': 15.0,
                    'total_score': 15.0,
                    'description': '根据提示写一篇英语短文',
                    'word_count': '80-100词',
                    'difficulty': {
                        '中等': 1
                    }
                }
            ]
        }
    },
    {
        'name': '初中英语期末考试卷',
        'description': '适用于初中英语期末考试，综合考查全学期知识点',
        'category': '初中英语',
        'total_score': 150.0,
        'paper_size': 'A3',
        'structure': {
            'header': {
                'title': '初中英语期末考试',
                'subtitle': '时间：120分钟  满分：150分',
                'instructions': '注意事项：\n1. 本试卷分为选择题和非选择题两部分。\n2. 答题前，请将姓名、班级、考号填写在答题卡上。'
            },
            'sections': [
                {
                    'title': '一、听力部分（共30分）',
                    'type': '单选题',
                    'count': 30,
                    'score_per_item': 1.0,
                    'total_score': 30.0
                },
                {
                    'title': '二、单项选择（共15分）',
                    'type': '单选题',
                    'count': 15,
                    'score_per_item': 1.0,
                    'total_score': 15.0
                },
                {
                    'title': '三、完形填空（共15分）',
                    'type': '完形填空',
                    'count': 15,
                    'score_per_item': 1.0,
                    'total_score': 15.0,
                    'passages': 1
                },
                {
                    'title': '四、阅读理解（共40分）',
                    'type': '阅读理解',
                    'count': 20,
                    'score_per_item': 2.0,
                    'total_score': 40.0,
                    'passages': 4
                },
                {
                    'title': '五、任务型阅读（共10分）',
                    'type': '任务型阅读',
                    'count': 5,
                    'score_per_item': 2.0,
                    'total_score': 10.0
                },
                {
                    'title': '六、词汇与语法（共15分）',
                    'type': '语法填空',
                    'count': 15,
                    'score_per_item': 1.0,
                    'total_score': 15.0
                },
                {
                    'title': '七、翻译（共10分）',
                    'type': '翻译',
                    'count': 5,
                    'score_per_item': 2.0,
                    'total_score': 10.0
                },
                {
                    'title': '八、书面表达（共15分）',
                    'type': '书面表达',
                    'count': 1,
                    'score_per_item': 15.0,
                    'total_score': 15.0
                }
            ]
        }
    },
    {
        'name': '初中英语专项训练-阅读理解',
        'description': '专注于阅读理解能力训练',
        'category': '初中英语',
        'total_score': 100.0,
        'paper_size': 'A4',
        'structure': {
            'header': {
                'title': '阅读理解专项训练',
                'subtitle': '时间：60分钟  满分：100分'
            },
            'sections': [
                {
                    'title': '一、阅读理解（选择题）',
                    'type': '阅读理解',
                    'count': 30,
                    'score_per_item': 2.0,
                    'total_score': 60.0,
                    'passages': 6
                },
                {
                    'title': '二、任务型阅读',
                    'type': '任务型阅读',
                    'count': 10,
                    'score_per_item': 2.0,
                    'total_score': 20.0,
                    'passages': 2
                },
                {
                    'title': '三、阅读与写作',
                    'type': '书面表达',
                    'count': 1,
                    'score_per_item': 20.0,
                    'total_score': 20.0,
                    'description': '阅读材料后，根据要求写作'
                }
            ]
        }
    }
]


def get_question_type_info(question_type):
    """获取题型信息"""
    return ENGLISH_QUESTION_TYPES.get(question_type, {})


def get_all_question_types():
    """获取所有支持的题型列表"""
    return list(ENGLISH_QUESTION_TYPES.keys())


def get_template_by_name(name):
    """根据名称获取模板"""
    for template in PRESET_TEMPLATES:
        if template['name'] == name:
            return template
    return None


def get_all_templates():
    """获取所有预设模板"""
    return PRESET_TEMPLATES
