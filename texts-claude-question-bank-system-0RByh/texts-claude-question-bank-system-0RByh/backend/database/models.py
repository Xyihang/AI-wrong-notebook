"""
数据库模型定义
"""
from datetime import datetime
from sqlalchemy import create_engine, Column, Integer, String, Text, DateTime, ForeignKey, Table, Float, JSON, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship, sessionmaker
import json as json_lib

Base = declarative_base()

# 题目-标签关联表（多对多）
question_tag_association = Table(
    'question_tag_association',
    Base.metadata,
    Column('question_id', Integer, ForeignKey('questions.id')),
    Column('tag_id', Integer, ForeignKey('tags.id'))
)

# 题库-题目关联表（多对多）
questionbank_question_association = Table(
    'questionbank_question_association',
    Base.metadata,
    Column('questionbank_id', Integer, ForeignKey('question_banks.id')),
    Column('question_id', Integer, ForeignKey('questions.id'))
)

# 试卷-题目关联表（多对多，带顺序）
class ExamPaperQuestion(Base):
    __tablename__ = 'exam_paper_questions'

    id = Column(Integer, primary_key=True)
    exam_paper_id = Column(Integer, ForeignKey('exam_papers.id'))
    question_id = Column(Integer, ForeignKey('questions.id'))
    order_index = Column(Integer)  # 题目在试卷中的顺序
    score = Column(Float, default=0.0)  # 该题分数

    question = relationship("Question")


class Question(Base):
    """题目表（支持复杂英语题型）"""
    __tablename__ = 'questions'

    id = Column(Integer, primary_key=True)
    content = Column(Text, nullable=False)  # 题目内容
    question_type = Column(String(50))  # 题型：单选题、阅读理解、完形填空等
    sub_type = Column(String(50))  # 子题型：如阅读理解的细节题、推理题等
    difficulty = Column(String(20))  # 难度：简单、中等、困难
    answer = Column(Text)  # 答案
    analysis = Column(Text)  # 解析
    source = Column(String(200))  # 来源（文件名等）

    # 扩展字段支持复杂题型（JSON格式）
    # 例如：选项、阅读材料、子题目列表等
    extra_data = Column(Text)  # JSON字符串

    # 父题目ID（用于阅读理解等有子题目的题型）
    parent_id = Column(Integer, ForeignKey('questions.id'), nullable=True)

    # 题目顺序（在父题目中的顺序）
    order_in_parent = Column(Integer, default=0)

    created_at = Column(DateTime, default=datetime.now)
    updated_at = Column(DateTime, default=datetime.now, onupdate=datetime.now)

    # 关联关系
    tags = relationship("Tag", secondary=question_tag_association, back_populates="questions")
    question_banks = relationship("QuestionBank", secondary=questionbank_question_association, back_populates="questions")

    # 子题目关系（自引用）
    sub_questions = relationship("Question", backref="parent", remote_side=[id])

    def get_extra_data(self):
        """获取扩展数据"""
        if self.extra_data:
            try:
                return json_lib.loads(self.extra_data)
            except:
                return {}
        return {}

    def set_extra_data(self, data):
        """设置扩展数据"""
        self.extra_data = json_lib.dumps(data, ensure_ascii=False)

    def __repr__(self):
        return f"<Question(id={self.id}, type={self.question_type})>"


class Tag(Base):
    """标签表"""
    __tablename__ = 'tags'

    id = Column(Integer, primary_key=True)
    name = Column(String(100), nullable=False, unique=True)  # 标签名称
    tag_type = Column(String(50))  # 标签类型：knowledge_point（知识点）、category（类别）等
    description = Column(Text)  # 标签描述
    created_at = Column(DateTime, default=datetime.now)

    # 关联关系
    questions = relationship("Question", secondary=question_tag_association, back_populates="tags")

    def __repr__(self):
        return f"<Tag(name={self.name}, type={self.tag_type})>"


class QuestionBank(Base):
    """题库表"""
    __tablename__ = 'question_banks'

    id = Column(Integer, primary_key=True)
    name = Column(String(200), nullable=False)  # 题库名称
    description = Column(Text)  # 题库描述
    created_at = Column(DateTime, default=datetime.now)
    updated_at = Column(DateTime, default=datetime.now, onupdate=datetime.now)

    # 关联关系
    questions = relationship("Question", secondary=questionbank_question_association, back_populates="question_banks")

    def __repr__(self):
        return f"<QuestionBank(name={self.name})>"


class ExamPaper(Base):
    """试卷表"""
    __tablename__ = 'exam_papers'

    id = Column(Integer, primary_key=True)
    name = Column(String(200), nullable=False)  # 试卷名称
    paper_size = Column(String(10), default='A4')  # 试卷尺寸：A4、A3
    total_score = Column(Float, default=100.0)  # 总分
    description = Column(Text)  # 试卷说明
    template_id = Column(Integer, ForeignKey('exam_templates.id'), nullable=True)  # 使用的模板
    created_at = Column(DateTime, default=datetime.now)
    updated_at = Column(DateTime, default=datetime.now, onupdate=datetime.now)

    # 关联关系
    paper_questions = relationship("ExamPaperQuestion", backref="exam_paper", cascade="all, delete-orphan")
    template = relationship("ExamTemplate", back_populates="exam_papers")

    def __repr__(self):
        return f"<ExamPaper(name={self.name}, size={self.paper_size})>"


class ExamTemplate(Base):
    """试卷模板表"""
    __tablename__ = 'exam_templates'

    id = Column(Integer, primary_key=True)
    name = Column(String(200), nullable=False)  # 模板名称
    description = Column(Text)  # 模板描述
    paper_size = Column(String(10), default='A4')  # 默认试卷尺寸
    total_score = Column(Float, default=100.0)  # 默认总分

    # 模板结构（JSON格式）
    # 定义各题型的数量、分值、难度分布等
    # 例如：{"sections": [{"type": "单选题", "count": 20, "score_per_item": 1.5, "difficulty": {"简单": 10, "中等": 8, "困难": 2}}]}
    structure = Column(Text, nullable=False)

    # 是否为系统预设模板
    is_system = Column(Boolean, default=False)

    # 适用科目/类别
    category = Column(String(100))  # 如：初中英语、高中数学等

    created_at = Column(DateTime, default=datetime.now)
    updated_at = Column(DateTime, default=datetime.now, onupdate=datetime.now)

    # 关联关系
    exam_papers = relationship("ExamPaper", back_populates="template")

    def get_structure(self):
        """获取模板结构"""
        if self.structure:
            try:
                return json_lib.loads(self.structure)
            except:
                return {"sections": []}
        return {"sections": []}

    def set_structure(self, data):
        """设置模板结构"""
        self.structure = json_lib.dumps(data, ensure_ascii=False)

    def __repr__(self):
        return f"<ExamTemplate(name={self.name}, category={self.category})>"
