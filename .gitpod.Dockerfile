FROM gitpod/workspace-full-vnc
                    
ENV TRIGGER_REBUILD 1

USER gitpod
RUN brew install zola
