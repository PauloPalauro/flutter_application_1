import asyncio
from typing import List
from fastapi import FastAPI, File, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, Response, JSONResponse, StreamingResponse
from pydantic import BaseModel
import cv2
import numpy as np
from ultralytics import YOLO
import cvzone
import math
import base64
import time
import os

app = FastAPI()

# Lista de conexões ativas
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
        print("WebSocket conectado")

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)
        print("WebSocket desconectado")

    async def send_message(self, message: str):
        if not self.active_connections:
            print("Nenhuma conexão ativa para enviar a mensagem.")
        for connection in self.active_connections:
            try:
                await connection.send_text(message)
            except Exception as e:
                print(f"Erro ao enviar mensagem: {e}")

manager = ConnectionManager()

# Carregar o modelo YOLO
model = YOLO("../../YOLO-Weights/ppe.pt")
model_person = YOLO("yolov8n.pt")
model_person.classes = [0]
classNames = ['Capacete', 'Máscara', 'SEM-Capacete', 'SEM-Máscara', 'SEM-Colete', 'Pessoa', 'Colete']
last_detection_message = None  # Variável global para armazenar a última mensagem de detecção


def analyze_image(img):
    # Inicializa uma flag para verificar se tudo está em ordem
    all_ok = True

    # Executar o modelo YOLO na imagem capturada
    results = model(img, stream=True)
    for r in results:
        boxes = r.boxes
        for box in boxes:
            # Caixa delimitadora
            x1, y1, x2, y2 = box.xyxy[0]
            x1, y1, x2, y2 = int(x1), int(y1), int(x2), int(y2)
            w, h = x2 - x1, y2 - y1

            # Confiança
            conf = math.ceil((box.conf[0] * 100)) / 100
            # Nome da Classe
            cls = int(box.cls[0])
            print(f"Índice da classe: {cls}")

            if cls < len(classNames):
                currentClass = classNames[cls]
            else:
                currentClass = "Desconhecido"
            
            print(currentClass)
            
            # Definir cores da caixa delimitadora e do texto
            if conf > 0.5:
                if currentClass in ['SEM-Capacete', 'SEM-Colete', 'SEM-Máscara']:
                    myColor = (0, 0, 255)  # Vermelho
                    all_ok = False  # Se algum item obrigatório estiver faltando, define all_ok como False
                elif currentClass in ['Capacete', 'Colete', 'Máscara']:
                    myColor = (0, 255, 0)  # Verde
                else:
                    myColor = (255, 0, 0)  # Azul

                # Desenhar caixa delimitadora e etiqueta
                cvzone.putTextRect(img, f'{classNames[cls]} {conf}',
                                   (max(0, x1), max(35, y1)), scale=2, thickness=2,
                                   colorB=myColor, colorT=(255, 255, 255), colorR=myColor, offset=6)
                cv2.rectangle(img, (x1, y1), (x2, y2), myColor, 3)

    return img, all_ok


async def generate_frames():
    cap = cv2.VideoCapture(0)  # Inicializar captura de vídeo com a webcam padrão
    cap.set(3, 1280)  # Definir largura
    cap.set(4, 720)   # Definir altura
    
    person_detected = False  # Flag para controlar a análise do YOLO
    detection_pause_time = 0  # Tempo de pausa após a detecção
    photo_taken = False  # Flag para controlar se a foto já foi tirada
    analysis_paused = False  # Flag para pausar a análise após tirar a foto

    while True:
        # Capturar frame
        success, img = cap.read()
        if not success:
            break
        
        current_time = time.time()  # Tempo atual

        # Se a pessoa ainda não foi detectada ou a pausa já terminou, executar o modelo YOLO
        if not person_detected or (current_time - detection_pause_time > 10):
            # Resetar a flag após o tempo de pausa
            if person_detected and (current_time - detection_pause_time > 10):
                person_detected = False  # Permitir nova detecção após a pausa
                if not photo_taken:
                    # Tira uma foto quando os 10 segundos de pausa terminam
                    photo_filename = f"webcam_photo_{int(current_time)}.jpg"
                    
                    result_img, all_ok = analyze_image(img)  # Chama a função de análise de imagem
                    photo_filename_result = f"result_photo_{int(current_time)}.jpg"
                    cv2.imwrite(photo_filename_result, result_img)  # Salvar a imagem analisada
                    print(f"Foto tirada e salva como {photo_filename_result}")
                    
                    await manager.send_message("Analise volta em 10")
                    
                    photo_taken = True  # Evitar tirar múltiplas fotos após a pausa

                    # Iniciar uma pausa de 5 segundos antes de continuar a análise
                    analysis_paused = True
                    pause_start_time = current_time

            # Executar o modelo YOLO no frame capturado apenas se a pausa de análise tiver terminado
            if not analysis_paused or (current_time - pause_start_time > 10):
                analysis_paused = False  # Pausa terminou, continuar análise
                results = model_person(img, stream=True, verbose=False, classes=[0])

                for r in results:
                    boxes = r.boxes
                    for box in boxes:
                        # Caixa delimitadora
                        x1, y1, x2, y2 = box.xyxy[0]
                        x1, y1, x2, y2 = int(x1), int(y1), int(x2), int(y2)

                        # Confiança
                        conf = math.ceil((box.conf[0] * 100)) / 100
                        # Nome da Classe
                        cls = int(box.cls[0])
                        
                        if cls == 0 and conf > 0.5:  # Verifica se é uma pessoa e se a confiança é alta
                            person_detected = True
                            detection_pause_time = current_time
                            photo_taken = False
                            print(f"Pessoa Detectada! Índice da classe: {cls}, Confiança: {conf}")

                            signal ="X"
                            await asyncio.sleep(0.1)  # Aguarda 100ms antes de enviar a mensagem
                            
                            try:
                                await manager.send_message(signal)
                            except Exception as e:
                                print(f"Erro ao enviar mensagem via WebSocket: {e}")
              
                            # Definir cor da caixa delimitadora
                            myColor = (0, 255, 0)  # Verde
                            cv2.rectangle(img, (x1, y1), (x2, y2), myColor, 3)

                            # Desenhar texto com a confiança
                            cvzone.putTextRect(img, f'Pessoa {conf:.2f}',  # Exibir confiança
                                               (max(0, x1), max(35, y1)), scale=2, thickness=2,
                                               colorB=myColor, colorT=(255, 255, 255), offset=6)

        # Converter o frame para o formato JPEG
        ret, buffer = cv2.imencode('.jpg', img)
        frame = buffer.tobytes()

        # Usar gerador para saída de frames
        yield (b'--frame\r\n'
               b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')

    cap.release()


@app.get("/", response_class=FileResponse)
async def index():
    # Certifique-se de que o caminho para o index.html esteja correto
    return FileResponse("index.html")


@app.get("/video_feed")
async def video_feed():
    # Gera o feed de vídeo usando StreamingResponse
    return StreamingResponse(generate_frames(), media_type="multipart/x-mixed-replace; boundary=frame")


@app.get("/result_photo/{filename}")
async def result_photo(filename: str):
    file_path = os.path.join(os.getcwd(), filename)
    if os.path.exists(file_path):
        return FileResponse(file_path)
    else:
        return JSONResponse(status_code=404, content={"message": "File not found"})


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    
    # Se houver uma mensagem anterior de detecção, envie-a ao cliente após a conexão
    if last_detection_message:
        await manager.send_message(last_detection_message)
    
    try:
        while True:
            data = await websocket.receive_text()
            print(f"Mensagem recebida do cliente: {data}")
    except WebSocketDisconnect:
        manager.disconnect(websocket)
        print("Cliente desconectado")
        

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
