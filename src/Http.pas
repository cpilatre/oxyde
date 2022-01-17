unit Http;

{$MODE Delphi}

{ Http : Permet la reception et l'envoi de message HTTP jusqu'à la version 1.0
  Date : Juin 2000
  Auteur : Claude Pilatre
  Utilise : Stream }

interface

uses Windows, SysUtils, Classes, Stream, Winsock;

const
{___________________________________  RFC 1945  ___________________________________}

  { Règles de base }
  _BYTE   = [#0..#255];        { toute donnée codée sur 8 bits }
  _CHAR   = [#0..#127];        { tout caractère ASCII-US (0 à 127) }
  UPALPHA = ['A'..'Z'];        { Tout caractère alphabétique ASCII-US majuscule A..Z }
  LOALPHA = ['a'..'z'];        { Tout caractère alphabétique ASCII-US minuscule a..z }
  ALPHA   = UPALPHA + LOALPHA; { Majuscule et minuscule }
  DIGIT   = ['0'..'9'];        { tout digit ASCII-US 0..9 }
  CTL     = [#0..#31, #127];   { Tous caractère de contrôle ASCII-US (0 à 31) et DEL (127) }
  CR      = #13;               { CR ASCII-US, retour chariot (13) }
  LF      = #10;               { LF ASCII-US, saut de ligne (10) }
  SP      = #32;               { SP ASCCII-US, espace (32) }
  HT      = #9;                { HT ASCII-US, tabulation horizontale (9) }
  QUOTE   = #34;               { double guillemet ASCII-US (34) }
  CRLF    = CR + LF;
  HEX     = ['a'..'f', 'A'..'F'] + DIGIT;

  SPECIALS = ['(', ')', '<', '>' , '@', ',', ';', ':', '\', '"', '/', '[', ']', '?',
              '=', '{', '}', SP, HT];

  TOKEN = _CHAR - CTL - [SP, ':'] ;
  TEXT = _BYTE - CTL + [CR, LF, HT];

  HttpVersion = 'HTTP/1.0';

  { Formats de temps et de date }
  DATE_RFC1123 = 0; { rfc1123-date = dweek "," SP date1 SP time SP "GMT" }
  DATE_RFC850  = 1; { rfc850-date = dayweek "," SP date2 SP time SP "GMT" }
  DATE_ASCTIME = 2; { asctime-date = dweek SP date3 SP time SP 4DIGIT }

  FMT_ASCTIME = '%s %s %2d %.2d:%.2d:%.2d %.4d';
  FMT_RFC850  = '%s, %.2d-%s-%s %.2d:%.2d:%.2d GMT';
  FMT_RFC1123 = '%s, %.2d %s %.4d %.2d:%.2d:%.2d GMT';

  { Utilisé pour le codage des dates }
  dweek: array[0..6] of string = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
  dayweek: array[0..6] of string = ('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday',
                                    'Friday', 'Saturday');
  month: array[1..12] of string = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
                                   'Sep', 'Oct', 'Nov', 'Dec');

  { Code d'état de la requete }
  STATUSCODE_OK                  = 200; { Ok }
  STATUSCODE_CREATED             = 201; { Créé }
  STATUSCODE_ACCEPTED            = 202; { Accepté }
  STATUSCODE_NOCONTENT           = 204; { Pas de contenu }
  STATUSCODE_MOVED_PERMANENTLY   = 301; { Changement d'adresse définitif }
  STATUSCODE_MOVED_TEMPORARILY   = 302; { Changement temporaire }
  STATUSCODE_NOTMODIFIED         = 304; { Non modifié }
  STATUSCODE_BADREQUEST          = 400; { Requête incorrecte }
  STATUSCODE_UNAUTHORIZED        = 401; { Non autorisé }
  STATUSCODE_FORBIDDEN           = 403; { Interdit }
  STATUSCODE_NOTFOUND            = 404; { Non trouvé }
  STATUSCODE_INTERNALSERVERERROR = 500; { Erreur interne serveur}
  STATUSCODE_NOTIMPLEMENTED      = 501; { Non implémenté }
  STATUSCODE_BADGATEWAY          = 502; { Erreur de routeur }
  STATUSCODE_SERVICEUNAVAILABLE  = 503; { Indisponible }

type
 SetOfChar = set of Char;
 StreamDirection = (sdIn, sdOut);

 RequestPart = packed record
   Method, URI, QueryString: string;
   Version: WORD;
 end;

 { ___ Classe Http ___ }

 HttpStream = class(TObject)
 protected
   Request: RequestPart;
   Header: TStringList;
   Body: PChar;
   ResponseLine: string;
   fStatus: Integer;
   fDirection: StreamDirection;

   { _ Response _ }

   { Renvoie un chaine de caractère correspondant au code d'état de la réponse }
   function getMessageStatus(Code: Integer): string;
   { Renvoie l'entête d'une réponse sous forme de chaine }
   function makeHeader: string;
   { Positionne le code de réponse }
   procedure setStatus(Value: Integer);
   { Ecrit les Size premiers octets de Buffer dans la socket csStream }
   function writeStream(csStream: CustomSocket; Buffer: PChar; Size: Integer): Integer;

   { _ Request _ }

   { Remplie l'objet Header à partir d'une chaine }
   procedure parseHeader(hdr: string);
   { Renseigne la structure Request à partir d'une ligne d'entête }
   procedure getRequestPart(rqst: string);
   { Extrait les données d'une requête à partir d'un Buffer de Size octets. }
   function readStream(Data: PChar; Size: Integer): Boolean;

   { _ Custom _ }

   { Corrige une chaine en remplaçant les chaines passées sous le format %xx
     en leur équivalent en caractère }
   function getCharURI(URI: string): string;
   { Change l'utilisation de l'objet : sdIn (requête) ou sdOut (réponse) }
   procedure setStreamDirection(sd: StreamDirection);
   { Renvoie la première ligne (terminée par CRLF). Si Multiple est à vrai renvoie toutes
     les lignes suivantes qui commencent par SP ou HT. }
   function getLine(var Src: string; Multiple: Boolean): string;
   { Renvoie le premier lexeme d'une chaine de caractère. Delimiters est un ensemble
     de caractères qui, si IsDelimiter est vrai, correspondent aux séparateurs de champ.
     Si IsDelimiter est faux Il correspondent aux caractères acceptés dans un lexeme. }
   function getToken(var Src: string; Delimiters: SetOfChar; IsDelimiter: Boolean): string;

 public
   { _ Response _ }

   property Status: Integer read fStatus write setStatus;
   { Positionne le code de réponse avec en plus un message particulier }
   procedure setStatusMsg(Code: Integer; Msg: string);
   { Indique la taille du corps de la réponse }
   procedure setContentLength(Lgth: Integer);
   { Indique le type MIME du corps de la réponse }
   procedure setContentType(TypeMIME: string);
   { Ajoute une valeur à l'entête sous la forme 'Name: Value' }
   procedure setHeader(Name, Value: string);
   { Fait la même chose que précédement mais à partir d'une valeur entière }
   procedure setIntHeader(Name: string; Value: Integer);
   { Fait la même chose que précédement mais à partir d'une date. }
   procedure setDateHeader(Name: string; pst: PSystemTime);
   { construit une réponse et y ajoute le fichier hFile puis écrit le tout dans la socket
     csStream. SingleResponse à vrai permet d'envoyer une réponse compatible HTTP/0.9.
     Appelle en interne writeStream }
   function writeStreamWithFile(csStream: CustomSocket; hFile: THandle; SingleResponse: Boolean): Boolean;
   { Construit l'entête de la réponse et l'écrit dans la socket csStream.
     Appelle en interne writeStream }
   function writeStreamHeaderOnly(csStream: CustomSocket): Boolean;
   { Envoie un message d'erreur dans la socket csStram.
     Appelle en interne writeStream }
   function sendInformation(csStream: CustomSocket; Code: Integer): Boolean;

   { _ Request _ }

   property Method: string read Request.Method;
   property URI: string read Request.URI;
   property QueryString: string read Request.QueryString;
   property Version: WORD read Request.Version;
   { Lit une requête à partir de la socket csStream. TimeOut correspond au nombre de
     secondes que l'on accepte d'attendre pour avoir une requête.
     Appelle en interne readStream. }
   function readStreamFromSocket(csStream: CustomSocket; TimeOut: DWORD): Integer;
   { Renvoie la valeur d'un paramètre. Utilise getQueryString }
   function getQueryParameter(Name: string): string;
   { Renvoie la valeur d'un champs de l'entête }
   function getHeader(Name: string): string;
   { Renvoie la valeur entière d'un champs de l'entête }
   function getIntHeader(Name: string; Dflt: Integer): Integer;
   { Renvoie la valeur date d'un champs de l'entête }
   function getDateHeader(Name: string): TSystemTime;
   { Renvoie le nom du Idx ième champs de l'entête }
   function getHeaderName(Idx: Integer): string;
   { Renvoie la valeur du Idx ième champs de l'entête }
   function getHeaderByIndex(Idx: Integer): string;

   { Custom }
   property Direction: StreamDirection read fDirection write setStreamDirection;
   { Renvoie une date suivant trois formats : RFC850, RFC1123 et asctime.
     Si pst vaut nil c'est la date du jour qui est utilisée. }
   function getDate(pst: PSystemTime; DateFormat: DWORD): string;
   { Ce constructeur lance immédiatement la récupération d'une requête sur la socket
     csStream en attendant au maximum TimeOut secondes. }
   constructor Create(csStream: CustomSocket; TimeOut: DWORD);
   destructor Destroy; override;
 end;

implementation

{__________________________________________________________________________________________

 HttpStream.Response
 __________________________________________________________________________________________}

{ Renvoie le message d'erreur en fonction d'un code }

function HttpStream.getMessageStatus(Code: Integer): string;
begin
  case Code of
    STATUSCODE_OK                  : Result := 'OK';
    STATUSCODE_CREATED             : Result := 'Created';
    STATUSCODE_ACCEPTED            : Result := 'Accepted';
    STATUSCODE_NOCONTENT           : Result := 'No Content';
    STATUSCODE_MOVED_PERMANENTLY   : Result := 'Moved Permanently';
    STATUSCODE_MOVED_TEMPORARILY   : Result := 'Moved Temporarily';
    STATUSCODE_NOTMODIFIED         : Result := 'Not Modified';
    STATUSCODE_BADREQUEST          : Result := 'Bad Request';
    STATUSCODE_UNAUTHORIZED        : Result := 'Unauthorized';
    STATUSCODE_FORBIDDEN           : Result := 'Forbidden';
    STATUSCODE_NOTFOUND            : Result := 'Not Found';
    STATUSCODE_INTERNALSERVERERROR : Result := 'Internal Server Error';
    STATUSCODE_NOTIMPLEMENTED      : Result := 'Not Implemented';
    STATUSCODE_BADGATEWAY          : Result := 'Bad Gateway';
    STATUSCODE_SERVICEUNAVAILABLE  : Result := 'Service Unavailable';
  else
    Result := '';
  end;
end;

{ Renvoie un chaine contenant l'entête du message (avec un ligne vide à la fin) }

function HttpStream.makeHeader: string;
var
  Idx: Integer;
  hdr: string;
begin
  { Concaténation ligne de réponse et en-tête }
  Result := ResponseLine + CRLF;
  for Idx := 0 to Header.Count - 1 do begin
    hdr := Header.Strings[Idx];
    hdr[Pos('=', Hdr)] := ':';
    Result := Result + hdr + CRLF;
  end;
  Result := Result + CRLF;
end;

{ Definit le code de retour d'une reponse }

procedure HttpStream.setStatus(Value: Integer);
begin
  setStatusMsg(Value, getMessageStatus(Value));
end;

{ Definit le code de retour d'une reponse avec un message particulier }

procedure HttpStream.setStatusMsg(Code: Integer; Msg: string);
begin
  ResponseLine := Format('%s %.3d %s', [HttpVersion, Code, Msg]);
  fStatus := Code;
end;

{ Insere (ou modifie) l'en-tête MIME Content-length }

procedure HttpStream.setContentLength(Lgth: Integer);
begin
  setIntHeader('Content-length', Lgth);
end;

{ Insere (ou modifie) l'en-tête MIME Content-type }

procedure HttpStream.setContentType(TypeMIME: string);
begin
  setHeader('Content-type', TypeMime);
end;

{ Insere (ou modifie) un en-tête MIME parmis :
    En-tête générale    : Date, Pragma
    En-tête de réponse  : Location, Server, WWW-Authenticate
    En-tête de l'entité : Allow, Content-Encoding, Content-Length, Content-Type,
                          Expires, Last-Modified }

procedure HttpStream.setHeader(Name, Value: string);
var
  Idx: Integer;
begin
  Idx := Header.IndexOfName(Name);
  if Idx <> -1 then
    Header.Delete(Idx);
  Header.Add(Name + '=' + Value);
end;

{ Insere (ou modifie) un en-tête MIME bis }

procedure HttpStream.setIntHeader(Name: string; Value: Integer);
begin
  setHeader(Name, IntToStr(Value));
end;

{ Insere (ou modifie) un en-tête MIME faisant référence à une date }

procedure HttpStream.setDateHeader(Name: string; pst: PSystemTime);
begin
  setHeader(Name, getDate(pst, DATE_RFC1123));
end;

{ Envoie une réponse }

function HttpStream.writeStream(csStream: CustomSocket; Buffer: PChar; Size: Integer): Integer;
begin
  Result := csStream.WriteData(Buffer, Size);
end;

{ Envoie une réponse à partir d'un HANDLE de fichier }

function HttpStream.writeStreamWithFile(csStream: CustomSocket; hFile: THandle;
                                        SingleResponse: Boolean): Boolean;
var
  res: string;
  TransmitBuffers: TTransmitFileBuffers;
begin
  Result := False;

  if SingleResponse then
    { Permet de gérer les réponses HTTP 0.9 }
    Result := csStream.TransmitFile(hFile, nil)
  else begin
    res := makeHeader();
    with TransmitBuffers do begin
      Head := PChar(res);
      HeadLength := Length(res);
      Tail := nil;
      TailLength := 0;
    end;
    Result := csStream.TransmitFile(hFile, @TransmitBuffers);
  end;
end;

{ Ne renvoie que l'entête du message (permet de gérer les requêtes HEAD) }

function HttpStream.writeStreamHeaderOnly(csStream: CustomSocket): Boolean;
var
  res: string;
begin
  res := makeHeader();
  Result := (writeStream(csStream, PChar(res), Length(res)) = Length(res));
end;

{ Renvoie un message d'erreur }

function HttpStream.sendInformation(csStream: CustomSocket; Code: Integer): Boolean;
var
  rsp: string;
begin
  setStatus(Code);
  rsp := ResponseLine + CRLF;
  Result := writeStream(csStream, PChar(rsp), Length(rsp)) = Length(rsp);
end;

{__________________________________________________________________________________________

 HttpStream.Request
 __________________________________________________________________________________________}

{ Decoupe la ligne de requête }

procedure HttpStream.getRequestPart(rqst: string);
var
  vers: string;
  i: Integer;
begin
  if rqst = '' then begin
    Request.Method := '';
    Request.URI := '';
    Request.QueryString := '';
    Request.Version := 0;
    Exit;
  end;

  { Récupère la méthode, }
  Request.Method := getToken(rqst, ALPHA, False);

  { l'URI ... }
  Request.URI := getToken(rqst, CTL + [SP], True);
  i := Pos('?', Request.URI);
  if i <> 0 then begin
    Request.QueryString := Copy(Request.URI, i + 1, MaxInt);
    SetLength(Request.URI, i - 1);
  end else
    Request.QueryString := '';
  Request.URI := getCharURI(Request.URI);

  { ... et la version }
  vers := getToken(rqst, ALPHA + DIGIT + ['.', '/'], False);
  if Pos('HTTP/', vers) = 1 then begin
    vers := Copy(vers, Pos('/', vers) + 1, MaxInt);
    Request.Version := MAKEWORD(StrToInt(Copy(vers, 1, Pos('.', vers) - 1)),
                                StrToInt(Copy(vers, Pos('.', vers) + 1, MaxInt)));
  end else
    { Version 0.9 de HTTP il n'y a donc pas d'en-tête ni de corps de message }
    Request.Version := MAKEWORD(0, 9);
end;

{ Remplie Header à partir d'une en-tête HTTP  }

procedure HttpStream.parseHeader(hdr: string);
var
  Line: string;
  i: Integer;
begin
  Header.Clear();
  Line := getLine(hdr, True);
  while Line <> '' do begin
    i := Pos(':', Line);
    if i = 0 then
      Break;
    Line[i] := '=';
    Header.Add(Line);
    Line := getLine(hdr, True);
  end;
end;

{ A partir d'un buffer récupère la ligne, l'en-tête et le corps de la requete }

function HttpStream.readStream(Data: PChar; Size: Integer): Boolean;
var
  Crt, OldCrt, Lst: PChar;
  rqst, tmpHeader: string;

  { Passe au plus "un caractère" de fin de ligne CRLF }
  procedure SkipCRLF;
  begin
    if (Crt < Lst) and (Crt^ in [CR, LF]) then Inc(Crt);
    if (Crt < Lst) and (Crt^ in [CR, LF]) then Inc(Crt);
  end;

begin
  Result := False;
  if Body <> nil then
    Body := PChar(GlobalFree(UINT(Body)));

  Crt := Data;
  Lst := Data + Size;

  { Récupération de la ligne de requete }
  while (Crt < Lst) and not (Crt^ in [CR, LF]) do
    Inc(Crt);
  SetString(rqst, Data, Integer(Crt - Data));
  getRequestPart(rqst);
  SkipCRLF();

  { On a affaire à une requete simple }
  if Crt >= Lst then begin
    Result := True;
    Exit;
  end;

  Data := Crt;

  { Récupération de l'en-tête }
  while True do begin
    OldCrt := Crt;
    while (Crt < Lst) and not(Crt^ in [CR, LF]) do Inc(Crt);
    if OldCrt = Crt then Break;
    SkipCRLF();
  end;
  if Crt >= Lst then
    Exit; { Erreur il doit manquer la ligne vide }
  SetString(tmpHeader, Data, Integer(Crt - Data));
  parseHeader(tmpHeader);
  SkipCRLF();

  { Récupération du coprs de la requete }
  if Crt < Lst then begin
    Body := PChar(GlobalAlloc(GMEM_FIXED, Integer(Lst - Crt)));
    CopyMemory(Body, Crt, Integer(Lst - Crt));
  end;

  Result := True;
end;

{ Lit le flux à partir d'un objet CustomSocket }

function HttpStream.readStreamFromSocket(csStream: CustomSocket; TimeOut: DWORD): Integer;
var
  Data: PChar;
begin
  { Récuperation de la taille des données et création du buffer}
  Result := csStream.GetDataSize(Timeout);
  if Result = 0 then { Après le Timeout on n'a toujours rien reçu alors on sort }
    Exit;
  Data := PChar(GlobalAlloc(GMEM_FIXED, Result));

  { Récupération des données }
  Result := csStream.ReadData(Data, Result);

  { Découpage de la requête }
  if (Result <> 0) and (not readStream(Data, Result)) then
    Result := 0;

  GlobalFree(UINT(Data));
end;

{ Renvoie la valeur d'un paramètre }

function HttpStream.getQueryParameter(Name: string): string;
var
  sz: string;
  i, NameLength: Integer;
begin
  Result := '';
  NameLength := Length(Name);
  sz := QueryString;
  while sz <> '' do begin
    i := Pos('&', sz);
    if i = 0 then
      i := MaxInt - 1; { car le Copy ne fonctionne pas avec (sz, MaxInt + 1, MaxInt) }
    if StrLIComp(PChar(Name), PChar(sz), NameLength) = 0 then begin
      Result := Copy(sz, NameLength + 2, i - NameLength - 2);
      Break;
    end;
    sz := Copy(sz, i + 1, MaxInt); { C'est là que cela risque de ne pas fonctionner }
  end;
end;

{ Renvoie la valeur de l'en-tête spécifié }

function HttpStream.getHeader(Name: string): string;
begin
  Result := Header.Values[Name];
end;

{ Renvoie la valeur entière de l'en-tête spécifié }

function HttpStream.getIntHeader(Name: string; Dflt: Integer): Integer;
var
  Code: Integer;
begin
  Val(getHeader(Name), Result, Code);
  if Code <> 0 then
    Result := Dflt;
end;

{ Renvoie une date à partir de l'en-tête spécifiée }

function HttpStream.getDateHeader(Name: string): TSystemTime;
var
  szDate, sztmp: string;
  Code: Integer;
  st: TSystemTime;

  { --- Le jour de la semaine --- }
  function getDayOfWeek: Boolean;
  begin
    st.wDayOfWeek := 0;
    while (st.wDayOfWeek < 7) and (sztmp <> dweek[st.wDayOfWeek]) do Inc(st.wDayOfWeek);
    result := (st.wDayOfWeek <> 7);
  end;

  { --- Le jour de la semaine --- }
  function getDayOfWeek2: Boolean;
  begin
    st.wDayOfWeek := 0;
    while (st.wDayOfWeek < 7) and (sztmp <> dayweek[st.wDayOfWeek]) do Inc(st.wDayOfWeek);
    result := (st.wDayOfWeek <> 7);
  end;

  { --- Le jour --- }
  function getDay: Boolean;
  begin
    sztmp := getToken(szDate, DIGIT, False);
    Val(sztmp, st.wDay, Code);
    Result := (Code = 0);
  end;

  { --- Le mois --- }
  function getMonth: Boolean;
  begin
   sztmp := getToken(szDate, ALPHA, False);
   st.wMonth := 1;
   while (st.wMonth < 13) and (sztmp <> month[st.wMonth]) do Inc(st.wMonth);
   Result := (st.wMonth <> 13);
  end;

  { --- L'année --- }
  function getYear: Boolean;
  begin
    sztmp := getToken(szDate, DIGIT, False);
    Val(sztmp, st.wYear, Code);
    Result := (Code = 0);
  end;

  { --- L'heure --- }
  function getTime: Boolean;
  begin
    sztmp := getToken(szDate, DIGIT + [':'], False);
    DecodeTime(StrToTime(sztmp), st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
    Result := True;
  end;

begin
  FillMemory(@Result, SizeOf(TSystemTime), 0); { Tout à zéro s'il y a une erreur }

  szDate := getHeader(Name);
  if szDate = '' then
    Exit;

  sztmp := getToken(szDate, ALPHA, False);
  if Length(sztmp) = 3 then begin

    { asctime et RFC1123 }
    { Le jour de la semaine }
    if not getDayOfWeek() then Exit;

    if (PChar(szDate)[0] = SP) then begin

      { --- asctime (Sun Nov 6 08:49:37 1994) --- }
      { Le mois - le jour - l'heure - l'année }
      if not (getMonth() and getDay() and getTime() and getYear())then
        Exit;

    end else

      { --- RFC1123 (Sun, 06 Nov 1994 08:49:37 GMT) --- }
      { Le jour - le mois - l'année - l'heure }
      if not (getDay() and getMonth() and getYear() and getTime()) then
        Exit;

  end else begin

    { --- RFC850 (Sunday, 06-Nov-94 08:49:37 GMT) --- }
    { Le jour de la semaine - le jour - le mois - l'année - l'heure }
    if not (getDayOfWeek2() and  getDay() and getMonth() and getYear() and
            getTime()) then Exit;

    { Correction de l'année car elle est envoyée sur deux caractères }
    if st.wYear < 70 then
      Inc(st.wYear, 2000)
    else
      Inc(st.wYear, 1900);

  end;

  Result := st;
end;

{ Renvoie la nom d'une valeur d'en-tête à partir de son index }

function HttpStream.getHeaderName(Idx: Integer): string;
begin
  Result := Header.Names[Idx];
end;

{ Renvoie la valeur de l'en-tête à partir de son index }

function HttpStream.getHeaderByIndex(Idx: Integer): string;
begin
  Result := Header.Values[Header.Names[Idx]];
end;

{__________________________________________________________________________________________

 HttpStream.Custom
 __________________________________________________________________________________________}

{ Renvoie une ligne se terminant par CRLF }

function HttpStream.getLine(var Src: string; Multiple: Boolean): string;
var
  Idx, k: Integer;
  ScrLength: Integer;
begin
  Result := '';
  Idx := 1;
  ScrLength := Length(Src);

 { Accepte tous les caractères non fin de ligne ou fin de buffer }
  while (Idx <= ScrLength) and not (Src[Idx] in [CR, LF]) do
    Inc(Idx);

  k := Idx;

  { Passe les caracteres de fin de ligne }
  while (Idx <= ScrLength) and (Src[Idx] in [CR, LF]) do Inc(Idx);

  if Multiple and (Idx <= ScrLength) and (Src[Idx] in [SP, HT]) then begin
    { Si les lignes sont multiples et que l'on doit les traiter on relance getLine }
    Result := Copy(Src, 1, Idx - 1);
    Delete(Src, 1, Idx - 1);
    Result := Result + getLine(Src, Multiple);
  end else begin
    { Ligne unique }
    Result := Copy(Src, 1, k - 1);
    Delete(Src, 1, Idx - 1);
  end;
end;

{ Renvoie un léxème en fonction des delimiteurs. Si IsDelimiter est à False
  Delimiters désignent en fait les caractères acceptés. }

function HttpStream.getToken(var Src: string; Delimiters: SetOfChar;
                             IsDelimiter: Boolean): string;
var
  Idx: Integer;
begin
  Result := '';
  Idx := 1;

  if not IsDelimiter then
    Delimiters := [#0..#255] - Delimiters;
  Delimiters := Delimiters + [#0];

  { Passe les délimiteurs du début }
  while (Src[Idx] <> #0) and (Src[Idx] in Delimiters) do
    Inc(Idx);

  while not(Src[Idx] in Delimiters) do begin
    Result := Result + Src[Idx];
    Inc(Idx);
  end;
  Src := Copy(Src, Idx, MaxInt);
end;

{ Convertit une URI composée de valeur en héxadecimale (par exemple %20 pour l'espace) }

function HttpStream.getCharURI(URI: string): string;
var
  Idx: Integer;
begin
  Idx := 1;
  Result := '';
  while (Idx <= Length(URI)) do begin
    if URI[Idx] = '%' then 
      if URI[Idx + 1] = '%' then begin
        Result := Result + '%';
        Inc(Idx, 2);
      end else begin
        Result := Result + Char(StrToInt('$' + URI[Idx + 1] + URI[Idx + 2]));
        Inc(Idx, 3);
      end
    else begin
      Result := Result + URI[Idx];
      Inc(Idx);
    end;
  end;
end;

{ Permet le changement de 'direction' }

procedure HttpStream.setStreamDirection(sd: StreamDirection);
begin
  fDirection := sd;
  if Body <> nil then
    Body := PChar(GlobalFree(UINT(Body)));
  Header.Clear();
  ResponseLine := '';
end;

{ Renvoie une date suivant plusieurs format (RFC850, RFC1123 ou asctime) }

function HttpStream.getDate(pst: PSystemTime; DateFormat: DWORD): string;
var
  st: TSystemTime;
begin
  if pst = nil then
    GetSystemTime(st)
  else
    st := pst^;

  if DateFormat = DATE_RFC850 then
    Result := Format(FMT_RFC850, [dayweek[st.wDayOfWeek], st.wDay, month[st.wMonth],
                     Copy(IntToStr(st.wYear), 3, 2), st.wHour, st.wMinute, st.wSecond])
  else if DateFormat = DATE_ASCTIME then
    Result := Format(FMT_ASCTIME, [dweek[st.wDayOfWeek], month[st.wMonth], st.wDay,
                                   st.wHour, st.wMinute, st.wSecond, st.wYear])
  else
    { DATE_RFC1123 par defaut }
    Result := Format(FMT_RFC1123, [dweek[st.wDayOfWeek], st.wDay, month[st.wMonth],
                                   st.wYear, st.wHour, st.wMinute, st.wSecond]);
end;

{ Constructeur utilisant une socket en entrée }

constructor HttpStream.Create(csStream: CustomSocket; TimeOut: DWORD);
begin
  inherited Create();

  Body := nil;
  Header := TStringList.Create();
  Header.Sorted := True;

  Direction := sdIn;
  if readStreamFromSocket(csStream, TimeOut) = 0 then
    Direction := sdOut;
end;

{ Le destructeur (durs les commentaires) }

destructor HttpStream.Destroy;
begin
  Header.Free();
  if Body <> nil then
    GlobalFree(UINT(Body));

  inherited Destroy;
end;

end.
