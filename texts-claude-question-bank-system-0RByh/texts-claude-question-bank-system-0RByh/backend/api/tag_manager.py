"""
标签管理API
"""
from typing import List, Dict, Any, Optional
from ..database import DatabaseManager, Tag


class TagManager:
    """标签管理器"""

    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager

    def create_tag(self, name: str, tag_type: str = 'knowledge_point',
                   description: Optional[str] = None) -> int:
        """
        创建标签
        :param name: 标签名称
        :param tag_type: 标签类型（knowledge_point/question_type/category等）
        :param description: 标签描述
        :return: 标签ID
        """
        return self.db.add_tag(name, tag_type, description)

    def get_all_tags(self, tag_type: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        获取所有标签
        :param tag_type: 标签类型筛选
        :return: 标签列表
        """
        tags = self.db.get_all_tags(tag_type)
        return [{
            'id': tag.id,
            'name': tag.name,
            'type': tag.tag_type,
            'description': tag.description,
            'question_count': len(tag.questions)
        } for tag in tags]

    def get_knowledge_points(self) -> List[Dict[str, Any]]:
        """获取所有知识点标签"""
        return self.get_all_tags(tag_type='knowledge_point')

    def get_question_types(self) -> List[Dict[str, Any]]:
        """获取所有题型标签"""
        return self.get_all_tags(tag_type='question_type')

    def delete_tag(self, tag_id: int) -> bool:
        """
        删除标签
        :param tag_id: 标签ID
        :return: 是否成功
        """
        session = self.db.get_session()
        try:
            tag = session.query(Tag).get(tag_id)
            if tag:
                session.delete(tag)
                session.commit()
                return True
            return False
        except Exception as e:
            session.rollback()
            raise e
        finally:
            session.close()

    def batch_create_tags(self, tags_data: List[Dict[str, str]]) -> Dict[str, Any]:
        """
        批量创建标签
        :param tags_data: 标签数据列表 [{'name': '代数', 'type': 'knowledge_point'}, ...]
        :return: 创建结果
        """
        success_count = 0
        failed_count = 0
        errors = []

        for tag_data in tags_data:
            try:
                self.create_tag(**tag_data)
                success_count += 1
            except Exception as e:
                failed_count += 1
                errors.append(str(e))

        return {
            'success_count': success_count,
            'failed_count': failed_count,
            'total': len(tags_data),
            'errors': errors
        }
