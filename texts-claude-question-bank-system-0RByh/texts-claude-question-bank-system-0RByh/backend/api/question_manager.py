"""
题目管理API
"""
from typing import List, Dict, Any, Optional
from ..database import DatabaseManager, Question, Tag, QuestionBank, ExamPaper, ExamPaperQuestion
from sqlalchemy.orm import Session


class QuestionManager:
    """题目管理器"""

    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager

    def create_question(self, content: str, question_type: Optional[str] = None,
                       difficulty: Optional[str] = None, answer: Optional[str] = None,
                       analysis: Optional[str] = None, source: Optional[str] = None,
                       tags: Optional[List[str]] = None) -> int:
        """
        创建题目
        :param content: 题目内容
        :param question_type: 题型
        :param difficulty: 难度
        :param answer: 答案
        :param analysis: 解析
        :param source: 来源
        :param tags: 标签列表
        :return: 题目ID
        """
        # 添加题目
        question_id = self.db.add_question(
            content=content,
            question_type=question_type,
            difficulty=difficulty,
            answer=answer,
            analysis=analysis,
            source=source
        )

        # 添加标签
        if tags:
            for tag_name in tags:
                tag_id = self.db.add_tag(tag_name)
                self.db.add_tag_to_question(question_id, tag_id)

        return question_id

    def update_question(self, question_id: int, **kwargs) -> bool:
        """
        更新题目信息
        :param question_id: 题目ID
        :param kwargs: 要更新的字段
        :return: 是否成功
        """
        session = self.db.get_session()
        try:
            question = session.query(Question).get(question_id)
            if not question:
                return False

            for key, value in kwargs.items():
                if hasattr(question, key):
                    setattr(question, key, value)

            session.commit()
            return True
        except Exception as e:
            session.rollback()
            raise e
        finally:
            session.close()

    def delete_question(self, question_id: int) -> bool:
        """
        删除题目
        :param question_id: 题目ID
        :return: 是否成功
        """
        session = self.db.get_session()
        try:
            question = session.query(Question).get(question_id)
            if question:
                session.delete(question)
                session.commit()
                return True
            return False
        except Exception as e:
            session.rollback()
            raise e
        finally:
            session.close()

    def get_question(self, question_id: int) -> Optional[Dict[str, Any]]:
        """
        获取题目详情
        :param question_id: 题目ID
        :return: 题目信息字典
        """
        session = self.db.get_session()
        try:
            question = session.query(Question).get(question_id)
            if not question:
                return None

            return {
                'id': question.id,
                'content': question.content,
                'question_type': question.question_type,
                'difficulty': question.difficulty,
                'answer': question.answer,
                'analysis': question.analysis,
                'source': question.source,
                'tags': [{'id': tag.id, 'name': tag.name, 'type': tag.tag_type} for tag in question.tags],
                'created_at': question.created_at.isoformat() if question.created_at else None,
                'updated_at': question.updated_at.isoformat() if question.updated_at else None
            }
        finally:
            session.close()

    def search_questions(self, tag_names: Optional[List[str]] = None,
                        question_type: Optional[str] = None,
                        difficulty: Optional[str] = None,
                        keyword: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        搜索题目
        :param tag_names: 标签名称列表
        :param question_type: 题型
        :param difficulty: 难度
        :param keyword: 关键词
        :return: 题目列表
        """
        session = self.db.get_session()
        try:
            query = session.query(Question)

            # 按标签筛选
            if tag_names:
                for tag_name in tag_names:
                    query = query.filter(Question.tags.any(Tag.name == tag_name))

            # 按题型筛选
            if question_type:
                query = query.filter(Question.question_type == question_type)

            # 按难度筛选
            if difficulty:
                query = query.filter(Question.difficulty == difficulty)

            # 按关键词筛选
            if keyword:
                query = query.filter(Question.content.like(f'%{keyword}%'))

            questions = query.all()

            return [{
                'id': q.id,
                'content': q.content,
                'question_type': q.question_type,
                'difficulty': q.difficulty,
                'answer': q.answer,
                'tags': [tag.name for tag in q.tags]
            } for q in questions]
        finally:
            session.close()

    def get_all_questions(self, limit: Optional[int] = None) -> List[Dict[str, Any]]:
        """
        获取所有题目
        :param limit: 限制数量
        :return: 题目列表
        """
        session = self.db.get_session()
        try:
            query = session.query(Question)
            if limit:
                query = query.limit(limit)

            questions = query.all()

            return [{
                'id': q.id,
                'content': q.content[:100] + '...' if len(q.content) > 100 else q.content,
                'question_type': q.question_type,
                'difficulty': q.difficulty,
                'tags': [tag.name for tag in q.tags],
                'created_at': q.created_at.isoformat() if q.created_at else None
            } for q in questions]
        finally:
            session.close()

    def batch_import_questions(self, questions_data: List[Dict[str, Any]]) -> Dict[str, Any]:
        """
        批量导入题目
        :param questions_data: 题目数据列表
        :return: 导入结果统计
        """
        success_count = 0
        failed_count = 0
        errors = []

        for idx, question_data in enumerate(questions_data):
            try:
                self.create_question(**question_data)
                success_count += 1
            except Exception as e:
                failed_count += 1
                errors.append(f"题目 {idx + 1}: {str(e)}")

        return {
            'success_count': success_count,
            'failed_count': failed_count,
            'total': len(questions_data),
            'errors': errors
        }
