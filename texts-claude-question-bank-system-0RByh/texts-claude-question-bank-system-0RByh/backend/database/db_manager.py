"""
数据库管理类
"""
import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, scoped_session
from .models import Base, Question, Tag, QuestionBank, ExamPaper, ExamPaperQuestion

class DatabaseManager:
    """数据库管理器"""

    def __init__(self, db_path='question_bank.db'):
        """初始化数据库连接"""
        self.db_path = db_path
        self.engine = create_engine(f'sqlite:///{db_path}', echo=False)
        self.Session = scoped_session(sessionmaker(bind=self.engine))

    def init_db(self):
        """初始化数据库（创建所有表）"""
        Base.metadata.create_all(self.engine)
        print("数据库初始化完成！")

    def get_session(self):
        """获取数据库会话"""
        return self.Session()

    def close_session(self):
        """关闭数据库会话"""
        self.Session.remove()

    def drop_all_tables(self):
        """删除所有表（慎用！）"""
        Base.metadata.drop_all(self.engine)
        print("所有表已删除！")

    def add_question(self, content, question_type=None, difficulty=None,
                    answer=None, analysis=None, source=None):
        """添加题目"""
        session = self.get_session()
        try:
            question = Question(
                content=content,
                question_type=question_type,
                difficulty=difficulty,
                answer=answer,
                analysis=analysis,
                source=source
            )
            session.add(question)
            session.commit()
            question_id = question.id
            return question_id
        except Exception as e:
            session.rollback()
            raise e
        finally:
            session.close()

    def add_tag(self, name, tag_type='knowledge_point', description=None):
        """添加标签"""
        session = self.get_session()
        try:
            # 检查标签是否已存在
            existing_tag = session.query(Tag).filter_by(name=name).first()
            if existing_tag:
                return existing_tag.id

            tag = Tag(name=name, tag_type=tag_type, description=description)
            session.add(tag)
            session.commit()
            tag_id = tag.id
            return tag_id
        except Exception as e:
            session.rollback()
            raise e
        finally:
            session.close()

    def add_tag_to_question(self, question_id, tag_id):
        """为题目添加标签"""
        session = self.get_session()
        try:
            question = session.query(Question).get(question_id)
            tag = session.query(Tag).get(tag_id)
            if question and tag:
                question.tags.append(tag)
                session.commit()
                return True
            return False
        except Exception as e:
            session.rollback()
            raise e
        finally:
            session.close()

    def create_question_bank(self, name, description=None):
        """创建题库"""
        session = self.get_session()
        try:
            bank = QuestionBank(name=name, description=description)
            session.add(bank)
            session.commit()
            bank_id = bank.id
            return bank_id
        except Exception as e:
            session.rollback()
            raise e
        finally:
            session.close()

    def add_question_to_bank(self, bank_id, question_id):
        """将题目添加到题库"""
        session = self.get_session()
        try:
            bank = session.query(QuestionBank).get(bank_id)
            question = session.query(Question).get(question_id)
            if bank and question:
                bank.questions.append(question)
                session.commit()
                return True
            return False
        except Exception as e:
            session.rollback()
            raise e
        finally:
            session.close()

    def get_questions_by_tags(self, tag_names=None, question_type=None):
        """根据标签和题型查询题目"""
        session = self.get_session()
        try:
            query = session.query(Question)

            if tag_names:
                for tag_name in tag_names:
                    query = query.filter(Question.tags.any(Tag.name == tag_name))

            if question_type:
                query = query.filter(Question.question_type == question_type)

            questions = query.all()
            return questions
        finally:
            session.close()

    def get_all_tags(self, tag_type=None):
        """获取所有标签"""
        session = self.get_session()
        try:
            query = session.query(Tag)
            if tag_type:
                query = query.filter_by(tag_type=tag_type)
            tags = query.all()
            return tags
        finally:
            session.close()

    def get_all_question_banks(self):
        """获取所有题库"""
        session = self.get_session()
        try:
            banks = session.query(QuestionBank).all()
            return banks
        finally:
            session.close()
