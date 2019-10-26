unit qiniu;

interface

type
  TNwUploadToQiniuStatus = (uqsUploaded, uqsUploadFail, uqsFileNotExists, uqsHttpNoneOK);
  TNwUpQiniuProgressCallback = reference to procedure(p: integer);

function uploadToQiniu( filename, token, key:string; progress:TNwUpQiniuProgressCallback ):TNwUploadToQiniuStatus;
function directUploadToQiniu( filename, token, key:string ):TNwUploadToQiniuStatus;

implementation
uses System.Net.HttpClient, System.Classes,System.Net.Mime, System.SysUtils,
system.Net.URLClient, Winapi.Windows, CommonFunction, System.Math, System.JSON,
System.netencoding, System.threading,SyncObjs;


function directUploadToQiniu( filename, token, key:string ):TNwUploadToQiniuStatus;
var
  http: THttpClient;
  data:TMultipartFormData;
  response:IHTTPResponse;
  content:string;
begin
  if not FileExists(filename) then
  begin
    Exit(uqsFileNotExists);
  end;
  Result := uqsUploadFail;
  http := THTTPClient.Create;
  data := TMultipartFormData.Create();
  try
    data.AddField('token', token);
    data.AddField('key', key);
    data.AddField('fileName', ExtractFileName(filename));
    data.AddFile('file', filename);
    response := http.Post('http://up-z2.qiniu.com/', data, nil);
    if response.StatusCode = 200 then
    begin
     Result := uqsUploaded;
    end
    else
      WinAPI.windows.OutputDebugString(PChar(Format('upload file:%s fail: %s, key: %s', [filename, response.ContentAsString(), key])));
  finally
    http.Free;
    data.Free;
  end;
end;


function uploadToQiniu( filename, token, key:string; progress:TNwUpQiniuProgressCallback ):TNwUploadToQiniuStatus;
const
  blocksize = 4*1024*1024;
  chunksize = 500*1024;
var
  filesize, blocks, okChuncks, chuncks:Cardinal;
  http: THttpClient;
  data:TBytesStream;
  response:IHTTPResponse;
  host,content:string;
  header:TNetHeaders;
  fileStream:TFileStream;
  responseValue:TJSonObject;
  ctxs:TArray<String>;
  lock:TCriticalSection;
begin
  if not FileExists(filename) then
  begin
    Exit(uqsFileNotExists);
  end;

  filesize := GetFileSize(filename);
  if filesize < 10*1024*1024 then
  begin
    Result := directUploadToQinu(filename, token, key );
    exit;
  end;

  blocks := Floor(filesize/blocksize);
  chuncks := Floor (filesize/chunksize);
  okChuncks := 0;

  host := 'http://up-z2.qiniup.com';
  Result := uqsUploadFail;
  http := THTTPClient.Create;
  data := TBytesStream.Create();
  insert(TNameValuePair.Create('Authorization', 'UpToken '+token), header, High(header));
  SetLength(ctxs, blocks+1);
  fileStream := TFileStream.Create(filename, fmShareDenyWrite or fmOpenRead);
  lock := TCriticalSection.Create;
   try
    TParallel.&For(0, blocks, procedure(Idx:Integer)
    var
      offset, currentChunkSize, currentBlockSize:Cardinal;
      data1:TBytesStream;
      lastCtx:string;
      http1: THttpClient;

    begin
       WinAPI.windows.
       OutputDebugString(PChar(Format('uploading block idx: %d', [Idx])));
       data1 := TBytesStream.Create();
       http1 := THTTPClient.Create;

       try
          offset := 0;
          currentBlockSize :=  Min(filesize-idx*blocksize, blocksize);

          //开始分片上传
          ///bput/<ctx>/<nextChunkOffset>
          while offset < currentBlockSize do
          begin
            data1.Clear;
            lock.Acquire;
            try
              filestream.Seek(idx*blocksize+offset, TSeekOrigin.soBeginning);
              currentChunkSize := Min(chunksize, currentBlockSize-offset);
              data1.CopyFrom(fileStream, currentChunkSize);
            finally
              lock.Release;
            end;

            //创建第一个块
            data1.Seek(0, TSeekOrigin.soBeginning);

            if offset = 0  then
              response := http1.Post(Format('%s/mkblk/%d', [host, currentBlockSize]), data1,nil, header)
            else
              response := http1.Post(Format('%s/bput/%s/%d', [host,lastCtx,offset]), data1,nil, header);

            if response.StatusCode = 200 then
            begin
              responseValue := TJSonObject.ParseJSONValue(response.ContentAsString(TEncoding.UTF8)) as TJSonObject;
              lastCtx := responseValue.GetValue('ctx').Value;
            end
            else
              Exit;

            inc(offset, currentChunkSize);
            inc(okChuncks);

            if Assigned(progress) then
              progress(Min(100, Round(okChuncks*100/chuncks)));
          end;
          ctxs[idx] := lastCtx;
       finally
         data1.Free;
         http1.Free;

       end;
    end);


    //合并文件
    ///mkfile/<fileSize>/key/<encodedKey>/fname/<encodedFname>/mimeType/<encodedMimeType>/x:user-var/<encodedUs
    data.Clear;
    with TStringStream.Create(''.Join(',', ctxs)) do begin
      SaveToStream(data);
      free;
    end;
    data.Seek(0, TSeekOrigin.soBeginning);
    // use content to store encoded key
    content := TBase64Encoding.Base64.Encode(key).Replace('+', '-').Replace('/', '_');

    response := http.Post(Format('%s/mkfile/%d/key/%s', [host, filesize, content]), data,nil, header);
      if response.StatusCode = 200 then
       Result := TNwUploadToQiniuStatus.uqsUploaded;
  finally
    http.Free;
    data.Free;
    fileStream.Free;
    lock.Free;
  end;

end;
end.
