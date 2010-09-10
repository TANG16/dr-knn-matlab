function [V, Vidx] = tangVects(X, types, varargin)
%
% TANGVECTS: Compute Tangent Vectors from Data
%
% Usage:
%   [V, Vidx] = tangVect(X, types, ...)
%
% Input:
%   X         - Input Data. Each column is an image.
%   types     - Tangent types [hvrspdtHV]+[k]K.
%               h: image horizontal translation
%               v: image vertical translation
%               r: image rotation
%               s: image scaling
%               p: image parallel hyperbolic transformation
%               d: image diagonal hyperbolic transformation
%               t: image trace thickening
%               H: image horizontal illumination
%               V: image vertical illumination
%               k: K nearest neighbors
%
% Input (optional):
%   'imSize',[W H]        - Image size (default=square)
%   'bw',BW               - Tangent derivative gaussian bandwidth (default=0.5)
%   'krh',KRH             - Supply tangent derivative kernel, horizontal
%   'krv',KRV             - Supply tangent derivative kernel, vertical
%   'basis',(true|false)  - Compute tangent basis (default=false)
%   'Xlabels',XLABELS     - Data class labels for kNN tangents
%
% Output:
%   V         - Tangent Vectors.
%   Vidx      - Indexes to the vectors in X from which the tangents correspond.
%
% $Revision$
% $Date$
%

%
% Copyright (C) 2008-2010 Mauricio Villegas (mvillegas AT iti.upv.es)
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program. If not, see <http://www.gnu.org/licenses/>.
%

if strncmp(X,'-v',2),
  unix('echo "$Revision$* $Date$*" | sed "s/^:/tangVects: revision/g; s/ : /[/g; s/ (.*)/]/g;"');
  return;
end

fn='tangVects:';
minargs=2;

%%% Default values %%%
V=[];
Vidx=[];

bw=0.5;
basis=false;

logfile=2;

%%% Input arguments parsing %%%
n=1;
argerr=false;
while size(varargin,2)>0,
  if ~ischar(varargin{n}) || size(varargin,2)<n+1,
    argerr=true;
  elseif strcmp(varargin{n},'imSize') || ...
         strcmp(varargin{n},'bw') || ...
         strcmp(varargin{n},'Xlabels') || ...
         strcmp(varargin{n},'krh') || ...
         strcmp(varargin{n},'krv'),
    eval([varargin{n},'=varargin{n+1};']);
    if ~isnumeric(varargin{n+1}),
      argerr=true;
    else
      n=n+2;
    end
  elseif strcmp(varargin{n},'basis'),
    eval([varargin{n},'=varargin{n+1};']);
    if ~islogical(varargin{n+1}),
      argerr=true;
    else
      n=n+2;
    end
  else
    argerr=true;
  end
  if argerr || n>size(varargin,2),
    break;
  end
end

[D,N]=size(X);

%%% Error detection %%%
if argerr,
  fprintf(logfile,'%s error: incorrect input argument %d (%s,%g)\n',fn,n+minargs,varargin{n},varargin{n+1});
  return;
elseif nargin-size(varargin,2)~=minargs,
  fprintf(logfile,'%s error: not enough input arguments\n',fn);
  return;
elseif ~ischar(types),
  fprintf(logfile,'%s error: types should be a string\n',fn);
  return;
elseif exist('Xlabels','var') && (max(size(Xlabels))~=N || min(size(Xlabels))~=1),
  fprintf(logfile,'%s error: labels must have the same size as the number of data points\n',fn);
  return;
end

imgtangs=false;
knntangs=false;
L=0;
n=1;
while n<=numel(types),
  if types(n)=='h' || types(n)=='v' || types(n)=='r' || types(n)=='s' || ...
     types(n)=='p' || types(n)=='d' || types(n)=='t' || ...
     types(n)=='H' || types(n)=='V',
    imgtangs=true;
    L=L+1;
    n=n+1;
  elseif types(n)=='k' || types(n)=='K',
    if types(n)=='K',
      rmtangs=true;
    end
    n=n+1;
    knntangs=str2num(types(n:end));
    types(n:end)=[];
    L=L+knntangs;
    if sum(size(knntangs))==0 || knntangs<1,
      fprintf(logfile,'%s error: type k should be the last one and be followed by the number of neighbors\n',fn);
      return;
    end
    if knntangs>=N || (exist('Xlabels','var') && knntangs>=min(hist(Xlabels,unique(Xlabels)))),
      fprintf(logfile,'%s error: not enough samples for %d nearest neighbors\n',fn,knntangs);
      return;
    end
  else
    fprintf(logfile,'%s error: types should be among [hvrspdtkHV]\n',fn);
    return;
  end
end

if numel(types)~=numel(unique(types)),
  fprintf(logfile,'%s error: types should not be repeated\n',fn);
  return;
end

if imgtangs,
  if ~exist('imSize','var'),
    imW=round(sqrt(D));
    imH=D/imW;
    imSize=[imW imH];
    if imH~=imW,
      fprintf(logfile,'%s error: if image is not square the size should be specified\n',fn);
      return;
    end
  end
  if ~exist('krv','var') || ~exist('krh','var'),
    krW=floor(16*bw);
    if krW<3,
      krW=3;
    end
    krH=krW;
    [krh,krv]=imgDervKern(krW,krH,bw);
  end

  xmin=-ceil(imSize(1)/2);
  ymin=-ceil(imSize(2)/2);

  x=[xmin:imSize(1)+xmin-1]';
  x=x(:,ones(imSize(2),1));
  y=[ymin:imSize(2)+ymin-1];
  y=y(ones(imSize(1),1),:);
end

if knntangs,
  x2=sum((X.^2),1);
  d=X'*X;
  d=x2(ones(N,1),:)'+x2(ones(N,1),:)-d-d;
  d([0:N-1]*N+[1:N])=inf;
  onesK=ones(knntangs,1);
end

if exist('rmtangs','var'),
  rmtangs=false(N*L,1);
end

V=zeros(D,N*L);
Vidx=repmat([1:N],L,1);
Vidx=Vidx(:);

for n=1:N,
  if imgtangs,
    im=reshape(X(:,n),imSize(1),imSize(2));
    derh=conv2(im,krh,'same');
    derv=conv2(im,krv,'same');

    mh=sum(sum(derh.*derh));
    mv=sum(sum(derv.*derv));
    mag=0.5*(sqrt(mh)+sqrt(mv));
  end

  v=zeros(D,L);
  nl=1;
  for l=1:numel(types),
    switch types(l)
      case 'h'
        v(:,nl)=derh(:);
      case 'v'
        v(:,nl)=derv(:);
      case 'r'
        v(:,nl)=reshape(-y.*derh-x.*derv,D,1);
      case 's'
        v(:,nl)=reshape(x.*derh-y.*derv,D,1);
      case 'p'
        v(:,nl)=reshape(x.*derh+y.*derv,D,1);
      case 'd'
        v(:,nl)=reshape(-y.*derh+x.*derv,D,1);
      case 't'
        v(:,nl)=derh(:).*derh(:)+derv(:).*derv(:);
      case 'H'
        v(:,nl)=reshape(x.*im,D,1);
      case 'V'
        v(:,nl)=reshape(y.*im,D,1);
    end

    if types(l)=='k',
      if exist('Xlabels','var'),
        sd=d(n,:);
        sd(Xlabels~=Xlabels(n))=inf;
        [sd,idx]=sort(sd);
      else
        [sd,idx]=sort(d(n,:));
      end
      v(:,nl:nl+knntangs-1)=X(:,idx(1:knntangs))-X(:,n(onesK));
      nl=nl+knntangs;
    elseif types(l)=='K',
      [sd,idx]=sort(d(n,:));
      sf=find(Xlabels(idx)~=Xlabels(n));
      kn=min(knntangs,sf(1)-1);
      v(:,nl:nl+kn-1)=X(:,idx(1:kn))-X(:,n(ones(kn,1)));
      v(:,nl+kn:nl+knntangs-1)=[];
      rmtangs((n-1)*L+nl+kn:n*L)=true;
      nl=nl+kn;
    else
      v(:,l)=v(:,l).*(mag/sqrt(sum(v(:,l).*v(:,l))));
      if types(l)>='A' && types(l)<='Z',
        v(:,l)=10*v(:,l);
      end
      nl=nl+1;
    end
  end

  if basis,
    [v,dummy]=qr(v,0);
  end

  V(:,(n-1)*L+1:(n-1)*L+size(v,2))=v;
end

if exist('rmtangs','var'),
  V(:,rmtangs)=[];
  Vidx(rmtangs)=[];
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [krh, krv] = imgDervKern(krW, krH, bandwidth)
%
% IMGDERVKERN: Compute Image Derivative Kernel
%
% Usage:
%   [krh, krv] = imgDervKern(krW, krH, bandwidth)
%
% Input:
%   krW       - Kernel Width.
%   krH       - Kernel Height.
%   bandwidth - Bandwidth.
%
% Output:
%   krh       - Horizontal Kernel.
%   hrv       - Vertical Kernel.
%

xmin=-floor(krW/2);
ymin=-floor(krH/2);

x=xmin:xmin+krW-1;
x=x(ones(krH,1),:);
y=(ymin:ymin+krH-1)';
y=y(:,ones(krW,1));

bandwidth=bandwidth*bandwidth;

e=exp(-(x.*x+y.*y)./(2*bandwidth))/bandwidth;

krh=-x.*e;
krv=y.*e;

krh=(krh./sqrt(sum(sum(krh.*krh))))';
krv=(krv./sqrt(sum(sum(krv.*krv))))';
