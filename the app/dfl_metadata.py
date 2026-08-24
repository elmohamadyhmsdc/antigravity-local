"""
Antigravity Local - DFL Metadata Module
DeepFaceLab-compatible metadata writer for face images
"""

import struct
import io
from pathlib import Path
from typing import Dict, Any, Optional, List, Tuple
from dataclasses import dataclass, asdict
import json

import numpy as np
from PIL import Image


@dataclass
class DFLFaceInfo:
    """DeepFaceLab face metadata structure"""
    # Source info
    source_filename: str = ""
    source_rect: Tuple[int, int, int, int] = (0, 0, 0, 0)  # x, y, w, h
    source_landmarks: Optional[List[List[float]]] = None  # 68-point or 106-point
    
    # Face alignment
    image_to_face_mat: Optional[List[List[float]]] = None  # 2x3 affine matrix
    
    # Segmentation (XSeg)
    xseg_mask: Optional[np.ndarray] = None
    
    # Face type (full face, whole face, head, etc.)
    face_type: str = "whole_face"
    
    # Embedding (optional, for matching)
    embedding: Optional[List[float]] = None


class DFLMetadata:
    """
    DeepFaceLab metadata handler.
    Writes face information into JPEG headers for DFL compatibility.
    """
    
    # DFL uses custom APP15 marker for metadata
    MARKER_DFL = b'\xff\xef'  # APP15
    MARKER_COMMENT = b'\xff\xfe'  # COM marker
    
    def __init__(self):
        pass
    
    @staticmethod
    def _encode_metadata(face_info: DFLFaceInfo) -> bytes:
        """Encode face info to bytes for storage"""
        data = {
            'source_filename': face_info.source_filename,
            'source_rect': list(face_info.source_rect),
            'face_type': face_info.face_type,
        }
        
        if face_info.source_landmarks is not None:
            data['source_landmarks'] = face_info.source_landmarks
        
        if face_info.image_to_face_mat is not None:
            data['image_to_face_mat'] = face_info.image_to_face_mat
        
        if face_info.embedding is not None:
            data['embedding'] = face_info.embedding
        
        json_str = json.dumps(data, separators=(',', ':'))
        return json_str.encode('utf-8')
    
    @staticmethod
    def _decode_metadata(data: bytes) -> Optional[DFLFaceInfo]:
        """Decode face info from bytes"""
        try:
            json_data = json.loads(data.decode('utf-8'))
            info = DFLFaceInfo(
                source_filename=json_data.get('source_filename', ''),
                source_rect=tuple(json_data.get('source_rect', [0, 0, 0, 0])),
                face_type=json_data.get('face_type', 'whole_face'),
            )
            
            if 'source_landmarks' in json_data:
                info.source_landmarks = json_data['source_landmarks']
            
            if 'image_to_face_mat' in json_data:
                info.image_to_face_mat = json_data['image_to_face_mat']
            
            if 'embedding' in json_data:
                info.embedding = json_data['embedding']
            
            return info
        except Exception as e:
            print(f"[WARNING] Failed to decode DFL metadata: {e}")
            return None
    
    def write_metadata(
        self,
        image_path: str,
        face_info: DFLFaceInfo,
        output_path: Optional[str] = None
    ) -> str:
        """
        Write DFL metadata into a JPEG image.
        
        Args:
            image_path: Path to source image
            face_info: DFLFaceInfo with face data
            output_path: Optional output path (defaults to overwriting input)
            
        Returns:
            Path to output image
        """
        output_path = output_path or image_path
        
        # Read image
        with open(image_path, 'rb') as f:
            img_data = f.read()
        
        # Encode metadata
        meta_bytes = self._encode_metadata(face_info)
        
        # Find start of image data (after FFD8)
        if img_data[:2] != b'\xff\xd8':
            raise ValueError("Not a valid JPEG file")
        
        # Create new image with metadata
        # Insert metadata right after SOI marker
        meta_segment = self._create_meta_segment(meta_bytes)
        
        # Find the position to insert (after FFD8, before next marker)
        new_data = img_data[:2] + meta_segment + img_data[2:]
        
        # Write output
        with open(output_path, 'wb') as f:
            f.write(new_data)
        
        return output_path
    
    def _create_meta_segment(self, meta_bytes: bytes) -> bytes:
        """Create a JPEG APP segment with metadata"""
        # Use COM (comment) marker for compatibility
        # Format: FF FE <length_2_bytes> <data>
        length = len(meta_bytes) + 2  # +2 for length bytes
        if length > 65535:
            raise ValueError("Metadata too large for JPEG segment")
        
        # Use a DFL identifier prefix
        prefix = b'DFLJPG\x00'
        data_with_prefix = prefix + meta_bytes
        length = len(data_with_prefix) + 2
        
        return self.MARKER_COMMENT + struct.pack('>H', length) + data_with_prefix
    
    def read_metadata(self, image_path: str) -> Optional[DFLFaceInfo]:
        """
        Read DFL metadata from a JPEG image.
        
        Args:
            image_path: Path to image
            
        Returns:
            DFLFaceInfo if found, None otherwise
        """
        with open(image_path, 'rb') as f:
            data = f.read()
        
        if data[:2] != b'\xff\xd8':
            return None
        
        # Search for COM marker with DFL prefix
        pos = 2
        while pos < len(data) - 4:
            if data[pos:pos+2] == self.MARKER_COMMENT:
                length = struct.unpack('>H', data[pos+2:pos+4])[0]
                segment_data = data[pos+4:pos+2+length]
                
                if segment_data.startswith(b'DFLJPG\x00'):
                    meta_bytes = segment_data[7:]  # Skip prefix
                    return self._decode_metadata(meta_bytes)
                
                pos += 2 + length
            elif data[pos:pos+1] == b'\xff':
                # Skip other markers
                if data[pos+1:pos+2] in [b'\xd0', b'\xd1', b'\xd2', b'\xd3', 
                                          b'\xd4', b'\xd5', b'\xd6', b'\xd7',
                                          b'\xd8', b'\xd9', b'\x00', b'\x01']:
                    pos += 2
                else:
                    try:
                        length = struct.unpack('>H', data[pos+2:pos+4])[0]
                        pos += 2 + length
                    except:
                        break
            else:
                break
        
        return None
    
    def create_dfl_faceset_image(
        self,
        face_image: np.ndarray,
        source_filename: str,
        bbox: Tuple[float, float, float, float],
        landmarks: Optional[np.ndarray] = None,
        embedding: Optional[np.ndarray] = None,
        output_path: str = None,
        face_type: str = "whole_face"
    ) -> str:
        """
        Create a DFL-compatible faceset image with metadata.
        
        Args:
            face_image: Face image array (BGR)
            source_filename: Original source filename
            bbox: Bounding box (x, y, w, h)
            landmarks: Optional facial landmarks
            embedding: Optional face embedding
            output_path: Path to save image
            face_type: DFL face type (whole_face, full_face, head)
            
        Returns:
            Path to created image
        """
        import cv2
        
        # Save image first
        cv2.imwrite(output_path, face_image)
        
        # Create face info
        face_info = DFLFaceInfo(
            source_filename=source_filename,
            source_rect=(int(bbox[0]), int(bbox[1]), int(bbox[2]), int(bbox[3])),
            face_type=face_type,
        )
        
        if landmarks is not None:
            face_info.source_landmarks = landmarks.tolist() if isinstance(landmarks, np.ndarray) else landmarks
        
        if embedding is not None:
            face_info.embedding = embedding.tolist() if isinstance(embedding, np.ndarray) else embedding
        
        # Write metadata
        self.write_metadata(output_path, face_info)
        
        return output_path


def convert_insightface_landmarks(landmarks_106: np.ndarray) -> List[List[float]]:
    """
    Convert InsightFace 106-point landmarks to DFL-compatible format.
    
    Args:
        landmarks_106: 106-point landmarks from InsightFace
        
    Returns:
        List of [x, y] coordinates
    """
    return landmarks_106.tolist()


if __name__ == "__main__":
    # Test metadata read/write
    import cv2
    
    # Create test image
    test_img = np.zeros((256, 256, 3), dtype=np.uint8)
    test_img[:] = (100, 100, 100)
    cv2.putText(test_img, "TEST", (50, 128), cv2.FONT_HERSHEY_SIMPLEX, 2, (255, 255, 255), 3)
    
    test_path = "test_dfl.jpg"
    cv2.imwrite(test_path, test_img)
    
    # Write metadata
    handler = DFLMetadata()
    face_info = DFLFaceInfo(
        source_filename="test_video.mp4",
        source_rect=(100, 100, 200, 200),
        face_type="whole_face"
    )
    
    handler.write_metadata(test_path, face_info)
    print(f"[INFO] Wrote metadata to {test_path}")
    
    # Read it back
    read_info = handler.read_metadata(test_path)
    if read_info:
        print(f"[INFO] Read metadata: source={read_info.source_filename}, rect={read_info.source_rect}")
    else:
        print("[ERROR] Failed to read metadata")
    
    # Cleanup
    import os
    os.remove(test_path)
    print("[INFO] Test completed successfully")
