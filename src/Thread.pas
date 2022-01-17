unit Thread;

{$MODE Delphi}

{ Thread  : Unité contenant la déclaration des threads qui traitent chaquent requête que
            reçoit le serveur.
  Date    : Juin 2000
  Auteur  : Claude Pilatre
  Utilise : Stream }

interface

uses
  Windows, Classes, SysUtils, Http, Stream, Config;

type

  { ___ Classe RequestThread ___ }

  { Chaque thread créé ne gèrent qu'une et une seule requête HTTP puis se termine. }
  RequestThread = class(TThread)
  private
    Params: pServerParams;
    csStream: CustomSocket;
    io: HttpStream;

    { Envoie la ressource spécifié par rsc. dfltStatusCode spécifie le code renvoyé
      si la ressource est disponible. InError permet d'indiquer si l'on gère ou non une
      erreur. Si ce n'est pas le cas sendURI peut être rappelée recursivement. }
    procedure sendURI(rsc: string; dfltStatusCode: Integer; InError: Boolean);
  protected
    procedure Execute; override;
  public
    constructor Create(Params: pServerParams; csStream: CustomSocket);
  end;

implementation

{__________________________________________________________________________________________

 RequestThread
 __________________________________________________________________________________________}

{ Permet d'envoyer une URI (un fichier plus particulièrement) }

procedure RequestThread.sendURI(rsc: string; dfltStatusCode: Integer; InError: Boolean);
label
  FileModified,
  CloseFileHandle;
var
  hFile: THandle;
  lpFileInformation: TByHandleFileInformation;
  IfModifiedSince, LastModified: TSystemTime;
  ftModifiedSince: TFileTime;
  Compare: Integer;
  Proto09: Boolean;

  procedure recursError(Code: Integer);
  begin
    if not InError then
      sendURI(Params^.ErrorFile, Code, True)
    else
      io.sendInformation(csStream, Code);
  end;

begin
  with io do begin

    { Récupération de la date de dernière modification que connait le client.
      On doit absoluement le faire avant la bascule en sortie de io (sdOut). }
    if not InError then begin
      IfModifiedSince := getDateHeader('If-Modified-Since');
      Proto09 := (Version = $0900);
    end;

    { Bascule de l'objet HttpStream en sortie }
    Direction := sdOut;

    { On précise le serveur (super ??) }
    setHeader('Server', Params^.Version);

    hFile := CreateFile(PChar(rsc), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
                        nil, OPEN_EXISTING, 0, 0);

    if hFile <> INVALID_HANDLE_VALUE then begin

      if Proto09 then
        { C'est la version 0.9 du protocole qui est utilisé }
        writeStreamWithFile(csStream, hFile, True)
      else
        { On récupère un certain nombre d'informations à propos de la ressource demandée }
        if GetFileInformationByHandle(hFile, lpFileInformation) then begin

          { Maintenant on regarde s'il y une date précisée dans l'en-tête If-Modified-Since }
          if (not InError) and (IfModifiedSince.wYear <> 0) then begin

            SystemTimeToFileTime(IfModifiedSince, ftModifiedSince);
            Compare := CompareFileTime(@ftModifiedSince, @lpFileInformation.ftLastWriteTime);

            { Le ressource à été modifiée on renvoie tout }
            if Compare = -1 then
              goto FileModified;

            { La ressource n'a pas été modifiée }
            if Compare in [0, 1] then
              sendInformation(csStream, STATUSCODE_NOTMODIFIED)
            else
              { Il y a une erreur }
              recursError(STATUSCODE_INTERNALSERVERERROR);

            { Il ne reste plus qu'à fermer le fichier }
            goto CloseFileHandle;

          end;

          FileModified:
            { Récupération d'informations }
            setContentLength(lpFileInformation.nFileSizeLow);
            setContentType(Params^.Mime.Value[ExtractFileExt(rsc)]);
            setDateHeader('Date', nil);
            Status := dfltStatusCode;

            if not InError then begin
              { Convertie la date de dernière écriture en date de dernière modification }
              FileTimeToSystemTime(lpFileInformation.ftLastWriteTime, LastModified);
              setDateHeader('Last-Modified', @LastModified);
            end;

            if (Method = 'HEAD') and (not InError) then
              writeStreamHeaderOnly(csStream)
            else
              { Le méthode est forcement GET }
              writeStreamWithFile(csStream, hFile, False);

          CloseFileHandle:
            { Fermeture du fichier }
            FileClose(hFile); { *Converti depuis CloseHandle* }

        end else { On n'a pas pu avoir des informations sur le fichier }
          recursError(STATUSCODE_INTERNALSERVERERROR);

    end else
      { hFile = INVALID_HANDLE_VALUE et là on essaie de savoir d'où vient l'erreur }
      case GetLastError() of
        ERROR_FILE_NOT_FOUND: recursError(STATUSCODE_NOTFOUND);
        ERROR_ACCESS_DENIED: recursError(STATUSCODE_FORBIDDEN);
      else
        recursError(STATUSCODE_INTERNALSERVERERROR);
      end;
  end;
end;

{ Le coeur du thread }

procedure RequestThread.Execute;
var
  rsc: string;
begin
  { Récupération de la requête et découpage des info contenues dans l'entête }
  io := HttpStream.Create(csStream, Params^.Timeout);

  { Traitement de la requête }
  try
    { Recupération de l'URI }
    rsc := Params^.DocumentRoot + io.URI;
    { Si l'URI n'indique pas de fichier particulier on utilise la valeur contenue
      dans DirectoryIndex }
    if io.URI = '/' then
      rsc := rsc + Params^.DirectoryIndex;

    { On ne prend en compte que les méthodes GET et HEAD }
    if (io.Method = 'GET') or (io.Method = 'HEAD') then
      sendURI(rsc, STATUSCODE_OK, False)
    else
      { Le méthode n'est pas gérée }
      sendURI(Params^.ErrorFile, STATUSCODE_NOTIMPLEMENTED, True)

  finally
    csStream.Shutdown(SD_BOTH);
    csStream.Free();
    io.Free();
  end;
end;

{ Le créateur (c'est pas Dieu c'est lui) }

constructor RequestThread.Create(Params: pServerParams; csStream: CustomSocket);
begin
  { Le thread s'éxecute tout de suite }
  inherited Create(False);
  { Le thread se détruira lors qu'il se terminera }
  FreeOnTerminate := True;

  { Récupération des paramètres }
  Self.Params := Params;
  Self.csStream := csStream;
end;

end.
