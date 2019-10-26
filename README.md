# 纯Delphi 原生写的 上传到七牛的功能。
### 上传文件到七牛， 支持分片分段上传， 适用于Delphi XE, 10等新版本

分两个函数： ```uploadToQiniu``` 和 ```directUploadToQiniu```

```uploadToQiniu``` 这个函数使用分片， 分段的方式上传， 并有上传进度回调， 采用多线程同时进行, 该方法适用于上传较大文件。

```directUploadToQiniu``` 该函数直接使用Form表单的形式上传， 没有上传进度回调， 适用于上传较小的文件。



上面两个方法已经使用于 [好智学项目](https://www.hzxue.com/)中， 被大量用户实际验证可行。


