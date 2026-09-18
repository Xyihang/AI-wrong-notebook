"""
OCR文本识别处理模块
支持图片和PDF文件的文本提取
"""
import os
from typing import List, Dict, Any
from paddleocr import PaddleOCR
from PIL import Image
import pdfplumber
from pdf2image import convert_from_path
import cv2
import numpy as np


class OCRProcessor:
    """OCR处理器"""

    def __init__(self, use_gpu=False, lang='en'):
        """
        初始化OCR处理器
        :param use_gpu: 是否使用GPU加速
        :param lang: 语言模式 'en'=英文, 'ch'=中文, 'en+ch'=中英文混合
        """
        # 英文优先配置
        self.ocr_en = PaddleOCR(
            use_angle_cls=True,
            lang='en',  # 英文
            use_gpu=use_gpu,
            show_log=False
        )

        # 中英文混合配置
        self.ocr_mix = PaddleOCR(
            use_angle_cls=True,
            lang='ch',  # 中文模式也能识别英文
            use_gpu=use_gpu,
            show_log=False
        )

        self.lang = lang
        self.ocr = self.ocr_en if lang == 'en' else self.ocr_mix

    def process_image(self, image_path: str, use_both=True) -> Dict[str, Any]:
        """
        处理图片文件，提取文本
        :param image_path: 图片路径
        :param use_both: 是否同时使用英文和中英文OCR进行识别
        :return: 识别结果字典
        """
        try:
            # 先用英文OCR识别
            result_en = self.ocr_en.ocr(image_path, cls=True)

            text_lines = []
            boxes = []
            confidences = []

            if result_en and result_en[0]:
                for line in result_en[0]:
                    box = line[0]  # 文本框坐标
                    text = line[1][0]  # 识别的文本
                    confidence = line[1][1]  # 置信度

                    text_lines.append(text)
                    boxes.append(box)
                    confidences.append(confidence)

            # 合并文本
            full_text = '\n'.join(text_lines)
            avg_conf = sum(confidences) / len(confidences) if confidences else 0

            # 如果启用双模式且置信度较低，再用中英文混合OCR识别
            mixed_text = None
            if use_both and avg_conf < 0.85:
                result_mix = self.ocr_mix.ocr(image_path, cls=True)

                text_lines_mix = []
                confidences_mix = []

                if result_mix and result_mix[0]:
                    for line in result_mix[0]:
                        text_lines_mix.append(line[1][0])
                        confidences_mix.append(line[1][1])

                mixed_text = '\n'.join(text_lines_mix)
                avg_conf_mix = sum(confidences_mix) / len(confidences_mix) if confidences_mix else 0

                # 如果混合模式置信度更高，使用混合模式结果
                if avg_conf_mix > avg_conf:
                    full_text = mixed_text
                    text_lines = text_lines_mix
                    confidences = confidences_mix
                    avg_conf = avg_conf_mix

            return {
                'success': True,
                'text': full_text,
                'text_lines': text_lines,
                'boxes': boxes,
                'confidences': confidences,
                'total_lines': len(text_lines),
                'avg_confidence': avg_conf,
                'mixed_text': mixed_text  # 保存混合模式的结果供参考
            }

        except Exception as e:
            return {
                'success': False,
                'error': str(e),
                'text': ''
            }

    def process_pdf(self, pdf_path: str, dpi=300) -> Dict[str, Any]:
        """
        处理PDF文件，提取文本
        :param pdf_path: PDF文件路径
        :param dpi: 转换图片的DPI，越高越清晰但处理越慢
        :return: 识别结果字典
        """
        try:
            all_text = []
            all_pages_data = []

            # 方法1：先尝试直接提取PDF中的文本（更快）
            with pdfplumber.open(pdf_path) as pdf:
                for page_num, page in enumerate(pdf.pages, 1):
                    text = page.extract_text()
                    if text and text.strip():
                        # 如果能直接提取到文本，使用这个方法
                        all_text.append(text)
                        all_pages_data.append({
                            'page': page_num,
                            'text': text,
                            'method': 'direct_extraction'
                        })

            # 方法2：如果直接提取失败或文本太少，使用OCR
            if not all_text or sum(len(t) for t in all_text) < 50:
                all_text = []
                all_pages_data = []

                # 将PDF转换为图片
                images = convert_from_path(pdf_path, dpi=dpi)

                for page_num, image in enumerate(images, 1):
                    # 将PIL图片转换为numpy数组
                    img_array = np.array(image)

                    # OCR识别
                    result = self.ocr.ocr(img_array, cls=True)

                    page_text_lines = []
                    if result and result[0]:
                        for line in result[0]:
                            text = line[1][0]
                            page_text_lines.append(text)

                    page_text = '\n'.join(page_text_lines)
                    all_text.append(page_text)

                    all_pages_data.append({
                        'page': page_num,
                        'text': page_text,
                        'lines': page_text_lines,
                        'method': 'ocr'
                    })

            # 合并所有页面的文本
            full_text = '\n\n'.join(all_text)

            return {
                'success': True,
                'text': full_text,
                'pages': all_pages_data,
                'total_pages': len(all_pages_data)
            }

        except Exception as e:
            return {
                'success': False,
                'error': str(e),
                'text': ''
            }

    def process_file(self, file_path: str) -> Dict[str, Any]:
        """
        自动识别文件类型并处理
        :param file_path: 文件路径
        :return: 识别结果
        """
        if not os.path.exists(file_path):
            return {
                'success': False,
                'error': '文件不存在'
            }

        ext = os.path.splitext(file_path)[1].lower()

        if ext == '.pdf':
            return self.process_pdf(file_path)
        elif ext in ['.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.webp']:
            return self.process_image(file_path)
        else:
            return {
                'success': False,
                'error': f'不支持的文件格式: {ext}'
            }

    def extract_questions_from_text(self, text: str) -> List[str]:
        """
        从文本中提取题目（支持英文题目编号）
        :param text: 文本内容
        :return: 题目列表
        """
        questions = []
        lines = text.split('\n')

        current_question = []
        # 支持英文题目编号：1., 2., Question 1, Q1, (1), etc.
        import re
        question_patterns = [
            r'^\d+\.',  # 1., 2., 3.
            r'^Question\s+\d+',  # Question 1, Question 2
            r'^Q\d+',  # Q1, Q2
            r'^\(\d+\)',  # (1), (2)
            r'^[A-Z]\.',  # A., B., C. (用于选项，但也可能是题目)
            r'^一、|^二、|^三、|^四、|^五、',  # 中文编号
            r'^（\d+）',  # 中文括号编号
        ]

        for line in lines:
            line = line.strip()
            if not line:
                continue

            # 检查是否是新题目的开始
            is_new_question = any(re.match(pattern, line) for pattern in question_patterns)

            if is_new_question and current_question:
                # 保存上一道题目
                questions.append('\n'.join(current_question))
                current_question = [line]
            else:
                current_question.append(line)

        # 保存最后一道题目
        if current_question:
            questions.append('\n'.join(current_question))

        return questions
