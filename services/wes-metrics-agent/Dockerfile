FROM python:3.8-alpine
RUN apk add --no-cache iproute2
COPY requirements.txt requirements.txt
RUN pip3 install --no-cache-dir -r requirements.txt
COPY . .
ENTRYPOINT [ "python", "main.py" ]
