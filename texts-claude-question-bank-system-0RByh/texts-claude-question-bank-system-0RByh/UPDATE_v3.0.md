# 题库系统 v3.0 更新说明

## 🎉 重大更新：全面支持英语题型 + 试卷模板系统

### ✨ 核心新功能

#### 1. 支持10种中国初中英语常见题型

系统现在完整支持中国初中英语考试的所有主流题型：

| 题型 | 英文名 | 特点 |
|------|--------|------|
| **单选题** | Multiple Choice | 四选一，测试语法、词汇、情景对话 |
| **完形填空** | Cloze Test | 在短文中选词填空，综合语言运用 |
| **阅读理解** | Reading Comprehension | 阅读文章后回答多个问题 |
| **任务型阅读** | Task-based Reading | 完成表格、信息匹配、回答问题 |
| **选词填空** | Word Selection | 从词库中选择合适的词填空 |
| **语法填空** | Grammar Filling | 根据语法规则填空（可能有提示词） |
| **单词拼写** | Spelling | 根据句意和首字母/音标写单词 |
| **句型转换** | Sentence Transformation | 改写句子保持意思不变 |
| **翻译** | Translation | 中英文互译 |
| **书面表达** | Writing | 根据要求写作文 |

每种题型都有：
- ✅ 详细的定义和描述
- ✅ 典型分值配置
- ✅ 子题型分类
- ✅ AI智能识别支持

#### 2. 试卷模板系统

**预设模板**（系统自带）：
1. **初中英语期中考试卷**（120分，A3）
   - 听力20分 + 单选15分 + 完形10分 + 阅读30分 + 任务型10分 + 词汇10分 + 语法10分 + 写作15分
   
2. **初中英语期末考试卷**（150分，A3）
   - 听力30分 + 单选15分 + 完形15分 + 阅读40分 + 任务型10分 + 词汇与语法15分 + 翻译10分 + 写作15分

3. **初中英语专项训练-阅读理解**（100分，A4）
   - 阅读理解60分 + 任务型阅读20分 + 阅读与写作20分

**模板功能**：
- ✅ 查看模板详细结构
- ✅ 模板统计分析（题型分布、难度分布）
- ✅ 一键使用模板自动生成试卷
- ✅ 创建自定义模板（付费功能可扩展）

**模板结构示例**：
```json
{
  "header": {
    "title": "初中英语期中考试",
    "subtitle": "时间：120分钟  满分：120分",
    "instructions": "注意事项..."
  },
  "sections": [
    {
      "title": "一、听力部分（共20分）",
      "type": "单选题",
      "count": 20,
      "score_per_item": 1.0,
      "difficulty": {
        "简单": 8,
        "中等": 10,
        "困难": 2
      }
    },
    ...
  ]
}
```

#### 3. 数据库扩展

**新增字段**：
- `Question.sub_type`: 子题型（如阅读理解的细节题、推理题等）
- `Question.extra_data`: JSON扩展数据（存储passage、choices等）
- `Question.parent_id`: 父题目ID（支持阅读理解多个子题目）
- `Question.order_in_parent`: 在父题目中的顺序

**新增表**：
- `ExamTemplate`: 试卷模板表
  - 模板结构（JSON）
  - 系统/自定义标识
  - 类别分类

**支持复杂结构**：
```python
# 阅读理解（父题目）
parent_question = {
    "content": "阅读下面短文...",
    "question_type": "阅读理解",
    "extra_data": {
        "passage": "完整的阅读材料...",
        "has_sub_questions": True
    }
}

# 子题目1
sub_question_1 = {
    "content": "1. What is the main idea?",
    "question_type": "阅读理解",
    "sub_type": "主旨大意",
    "parent_id": parent_question.id,
    "order_in_parent": 1,
    "extra_data": {
        "choices": ["A. ...", "B. ...", "C. ...", "D. ..."]
    }
}
```

#### 4. AI智能识别增强

**更新的识别能力**：

AI现在可以准确识别和分类：
- ✅ 10种英语题型
- ✅ 题目的子类型
- ✅ 题目结构（passage + sub-questions）
- ✅ 选择题选项
- ✅ 填空题的提示词
- ✅ 知识点标签

**AI Prompt优化**：
```
识别模式：
1. 单选题 → multiple_choice
2. 完形填空 → cloze_test（自动识别关联的passage）
3. 阅读理解 → reading_comprehension（识别父子题目关系）
4. 任务型阅读 → task_based_reading
5. 选词填空 → word_selection（识别word bank）
6. 语法填空 → grammar_filling（区分有/无提示词）
7. 单词拼写 → spelling
8. 句型转换 → sentence_transformation
9. 翻译 → translation
10. 书面表达 → writing
```

**识别示例**：
```json
{
  "question_number": 1,
  "content": "Read the passage and answer questions 1-5.",
  "question_type": "reading_comprehension",
  "sub_type": "detail_comprehension",
  "passage": "完整阅读材料...",
  "has_sub_questions": true,
  "choices": ["A. ...", "B. ...", "C. ...", "D. ..."],
  "tags": ["reading", "comprehension", "main_idea"],
  "difficulty": "medium"
}
```

### 🎯 使用场景

#### 场景1：使用模板快速生成试卷

```
1. 访问"试卷模板"页面
2. 查看预设模板（期中/期末/专项训练）
3. 点击"使用模板"
4. 输入试卷名称
5. 系统自动根据模板要求从题库选题
6. 生成完整试卷
```

#### 场景2：识别完形填空题

```
上传图片：
---
Cloze Test
Read the passage and choose the best answer.

Tom is a student. He _1_ to school every day. 
He _2_ very hard. His teacher _3_ him very much.

1. A. go    B. goes    C. going    D. went
2. A. study B. studies C. studied  D. studying
3. A. like  B. likes   C. liked    D. liking
---

AI识别结果：
{
  "question_type": "cloze_test",
  "passage": "Tom is a student...",
  "sub_questions": [
    {"number": 1, "choices": ["A. go", "B. goes", ...]},
    {"number": 2, "choices": ["A. study", ...]},
    {"number": 3, "choices": ["A. like", ...]}
  ],
  "tags": ["grammar", "verb_tense", "cloze_test"]
}
```

#### 场景3：自定义模板

```python
# 创建自定义专项训练模板
custom_template = {
    "name": "语法专项训练",
    "category": "初中英语",
    "total_score": 80,
    "structure": {
        "sections": [
            {
                "title": "一、时态专项",
                "type": "单选题",
                "sub_type": "语法",
                "count": 20,
                "score_per_item": 2.0,
                "tags": ["时态"]
            },
            {
                "title": "二、语法填空",
                "type": "语法填空",
                "count": 10,
                "score_per_item": 2.0
            },
            {
                "title": "三、句型转换",
                "type": "句型转换",
                "count": 10,
                "score_per_item": 2.0
            }
        ]
    }
}
```

### 📊 技术亮点

#### 1. 灵活的JSON数据存储

```python
# 题目可以存储任意扩展信息
question.set_extra_data({
    "passage": "完整文章...",
    "word_bank": ["choose", "from", "these", "words"],
    "images": ["image1.png", "image2.png"],
    "audio": "listening.mp3",
    "sub_questions": [...]
})
```

#### 2. 智能的父子题目关系

```python
# 查询阅读理解及其所有子题目
reading = session.query(Question).filter_by(id=parent_id).first()
sub_questions = reading.sub_questions  # 自动关联的子题目

# 按顺序排列子题目
sorted_subs = sorted(sub_questions, key=lambda x: x.order_in_parent)
```

#### 3. 模板驱动的组卷

```python
# 根据模板自动选题
paper_id = template_manager.generate_paper_from_template(
    template_id=1,
    paper_name="2024年春季期中考试",
    question_manager=question_manager
)

# 系统会：
# 1. 读取模板结构
# 2. 按题型、难度分布选题
# 3. 计算分数分配
# 4. 生成完整试卷
```

### 🚀 API新增端点

```
GET  /api/templates                      - 获取所有模板
GET  /api/templates/:id                  - 获取单个模板
POST /api/templates                      - 创建模板
PUT  /api/templates/:id                  - 更新模板
DELETE /api/templates/:id                - 删除模板
POST /api/templates/:id/generate         - 根据模板生成试卷
GET  /api/templates/:id/stats            - 获取模板统计
```

### 📁 新增文件

```
backend/
  ├── api/
  │   └── template_manager.py          # 模板管理器（新）
  ├── templates/                        # 模板配置（新）
  │   ├── __init__.py
  │   └── english_templates.py         # 英语题型和模板定义
  └── database/
      └── models.py                     # 扩展Question和ExamTemplate模型

frontend/
  ├── templates/
  │   ├── base.html                     # 添加模板导航
  │   └── templates.html               # 模板管理页面（新）
  └── static/
      ├── js/
      │   └── templates.js             # 模板管理逻辑（新）
      └── css/
          └── style.css                # 添加模板样式
```

### 🎓 教学建议

**对于英语教师**：
1. 使用预设模板快速生成期中期末试卷
2. 根据教学进度自定义模板（如专项语法训练）
3. 利用AI识别功能批量录入历年真题
4. 按知识点标签组织题库

**对于学生**：
1. 使用专项训练模板针对性练习
2. 按题型分类复习
3. 使用AI识别功能整理错题本

### 📈 性能优化

- ✅ JSON字段高效存储复杂数据
- ✅ 父子题目关系查询优化
- ✅ 模板结构缓存
- ✅ 批量题目选择优化

### 🔮 未来计划

- [ ] 更多学科模板（数学、物理、化学等）
- [ ] 听力题支持（音频文件管理）
- [ ] 智能组卷优化（知识点覆盖率分析）
- [ ] 试卷难度预测
- [ ] 题目推荐系统

### 📝 使用示例

**完整工作流程**：

```bash
# 1. 启动系统
python app.py

# 2. 访问 http://localhost:5000/templates

# 3. 选择"初中英语期中考试卷"模板

# 4. 点击"使用模板" → 输入"2024年春季期中考试"

# 5. 系统自动生成完整试卷：
#    - 听力20题（从题库选择）
#    - 单选15题（按难度分布）
#    - 完形填空10题（关联passage）
#    - 阅读理解15题（3篇文章 × 5题）
#    - ...

# 6. 导出Word文档（A3纸张，标准格式）
```

### ⚠️ 注意事项

1. **首次使用**：系统会自动初始化3个预设模板
2. **题库要求**：使用模板前确保题库中有相应题型和数量
3. **AI功能**：需要配置ANTHROPIC_API_KEY才能使用AI识别
4. **数据库升级**：v3.0自动扩展数据库schema，兼容旧数据

### 🆘 常见问题

**Q: 如何查看题库中各题型数量？**
A: 访问"题目管理"页面，使用筛选功能按题型查看

**Q: 模板生成试卷失败？**
A: 检查题库中相应题型数量是否足够，可以先导入更多题目

**Q: 如何修改预设模板？**
A: 系统模板不可修改，可以基于预设模板创建自定义模板

**Q: AI能识别手写题目吗？**
A: 可以，但建议使用清晰的打印体以获得最佳识别效果

---

**版本**: v3.0
**发布日期**: 2024-01-23
**兼容性**: 向后兼容 v2.0

祝使用愉快！🎉

**Git提交**: `a0e17de`
**分支**: `claude/question-bank-system-0RByh`
