FROM python:3.13.18-alpine3.24

RUN pip install --no-cache-dir pyftpdlib==2.2.0

COPY ftpserver.py /app/

USER nobody
WORKDIR /app
ENV PYTHONUNBUFFERED=1 \
    FTP_ROOT=/softwares/shelves \
    FTP_HOST=0.0.0.0 \
    FTP_PORT=2121 \
    FTP_PASSIVE=30000-30009

EXPOSE 2121 30000-30009
CMD ["python", "/app/ftpserver.py"]
